# 10 · Follow one pod down to the kernel

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 10](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#10-follow-one-pod-down-to-the-kernel)
>
> **You'll learn:** where `250m`, `500m` and `128Mi` end up, layer by layer: the runtime's spec, systemd, and the cgroup files.

## The question

Where exactly do the numbers in your `resources:` block end up?

## Predict first

<details>
<summary>The pod requests 64Mi of memory. Which cgroup file protects that memory for it?</summary>

None, by default. <code>memory.min</code> stays <code>0</code>. Kubernetes uses the memory request to choose a node and to rank pods for eviction, not to ask the kernel for protection.
</details>

## Steps

The pod uses the blog's numbers: requests `250m` / `64Mi`, limits `500m` / `128Mi`.

```bash
kubectl apply -f labs/10-follow-one-pod-down/pod.yaml
kubectl wait --for=condition=Ready pod/follow-me --timeout=120s
CID=$(kubectl get pod follow-me -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's#containerd://##')
```

**Layer 1, the runtime.** The kubelet hands containerd an OCI runtime spec. `crictl` shows what it asked for:

```bash
docker exec under-the-hood-worker crictl inspect $CID | grep -E '"cgroupsPath"|"shares"|"quota"|"period"|"limit"'
```

```text
"cgroupsPath": "kubelet-kubepods-burstable-pod97ea3d5e_c357_….slice:cri-containerd:…",
"period": 100000,
"quota": 50000,
"shares": 256
"limit": 134217728,
```

`shares: 256` is the 250m request in the old cgroup v1 unit (250 × 1024 / 1000).

**Layer 2, systemd.** runc asks systemd to create the cgroup as a *scope*:

```bash
docker exec under-the-hood-worker systemctl show cri-containerd-$CID.scope -p CPUWeight -p CPUQuotaPerSecUSec -p MemoryMax
```

```text
CPUWeight=35
CPUQuotaPerSecUSec=500ms
MemoryMax=134217728
```

**Layer 3, the kernel's files.** From the node, and from inside the container:

```bash
CDIR="$(./scripts/pod-cgroup.sh follow-me)/cri-containerd-$CID.scope"
docker exec under-the-hood-worker cat $CDIR/cpu.weight $CDIR/cpu.max $CDIR/memory.max
kubectl exec follow-me -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.weight /sys/fs/cgroup/memory.min
```

```text
35
50000 100000
134217728
50000 100000
134217728
35
0
```

**One process, two points of view:**

```bash
HPID=$(docker exec under-the-hood-worker head -n1 $CDIR/cgroup.procs)
docker exec under-the-hood-worker cat /proc/$HPID/comm /proc/$HPID/cgroup
kubectl exec follow-me -- cat /proc/1/comm /proc/self/cgroup
```

The same `sleep`: an ordinary PID and a long cgroup path on the node; PID 1 and `0::/` inside (lab 07).

## What happened

| You wrote | File | Value | In plain words |
|---|---|---|---|
| `limits.cpu: 500m` | `cpu.max` | `50000 100000` | At most 50 ms of CPU in every 100 ms |
| `limits.memory: 128Mi` | `memory.max` | `134217728` | 128 MiB; reclaim, then OOM kill |
| `requests.cpu: 250m` | `cpu.weight` | `35` | A share, only used when groups compete |
| `requests.memory: 64Mi` | `memory.min` | `0` | No kernel protection. Used for scheduling and eviction |

(Since Kubernetes 1.37, the `MemoryQoS` feature can protect memory requests with `memory.min`, but only if you opt in through the kubelet's `memoryReservationPolicy`. Left at its default, as here, it writes nothing.)

> **In one line:** `requests.cpu` → `cpu.weight`, `limits.cpu` → `cpu.max`, `limits.memory` → `memory.max`. The memory request is for scheduling and eviction.

Check your work: `make check LAB=10`

## Clean up

```bash
kubectl delete -f labs/10-follow-one-pod-down/ --ignore-not-found
```

**Next:** [lab 11 · The cgroup tree](../11-the-cgroup-tree/)
