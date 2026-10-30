# 02 · Follow one pod down to the kernel

**What you'll learn:** exactly how the `resources:` block in a pod becomes the cgroup files you built by hand in module 01, by stopping at every layer on the way down: the API, the container runtime, systemd, and the kernel.

**Time:** about 10 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## The journey

```text
pod.yaml  ──►  API server  ──►  kubelet  ──►  containerd + runc  ──►  systemd  ──►  /sys/fs/cgroup
 (you)        (stores it)     (on the node)   (container runtime)     (scope unit)    (the kernel)
```

## Step 1: Create the pod

```bash
kubectl create namespace lab            # skip if it already exists
kubectl -n lab apply -f modules/02-follow-the-pod/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/follow-me
```

[`pod.yaml`](pod.yaml) asks for `250m` CPU and `64Mi` memory, limited to `500m` and `128Mi`.

Grab the container's ID; we'll use it at every layer:

```bash
CID=$(kubectl -n lab get pod follow-me -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's#containerd://##')
echo $CID
```

## Step 2: What the kubelet asked the runtime for

The kubelet doesn't create cgroups itself. It sends the container runtime (containerd) a description of the container, in a standard format called the **OCI runtime spec**. `crictl` is the command-line tool for talking to the runtime directly:

```bash
docker exec under-the-hood-worker crictl inspect $CID | grep -E '"cgroupsPath"|"shares"|"quota"|"period"|"limit"'
```

```output
"cgroupsPath": "kubelet-kubepods-burstable-pod<uid>.slice:cri-containerd:<id>",
"shares": 256,
"quota": 50000,
"period": 100000,
"limit": 134217728,
```

**What it means:**

- **`cgroupsPath`** says where to put the container: inside its pod's slice, as a unit called `cri-containerd-<id>`.
- **`quota` / `period`** are your 500m CPU limit: 50 ms per 100 ms.
- **`limit`** is your 128Mi memory limit, in bytes.
- **`shares: 256`** is your 250m CPU *request*, in an older unit called CPU shares (`250 × 1024 / 1000 = 256`). The kubelet still describes requests this way; the runtime (runc) converts shares to the cgroup v2 `cpu.weight` when it builds the cgroup.

## Step 3: What systemd made of it

With the systemd cgroup driver, runc doesn't write the files directly either. It asks systemd to create a **scope** (systemd's name for a group of processes started by someone else) with these settings:

```bash
docker exec under-the-hood-worker systemctl show cri-containerd-$CID.scope -p CPUWeight -p CPUQuotaPerSecUSec -p MemoryMax
```

```output
CPUWeight=35
CPUQuotaPerSecUSec=500ms
MemoryMax=134217728
```

`CPUQuotaPerSecUSec=500ms` is the same 500m limit, described as "500 ms of CPU per second". `CPUWeight=35` is the converted request.

## Step 4: The files the kernel reads

```bash
CDIR="$(./scripts/pod-cgroup.sh follow-me)/cri-containerd-$CID.scope"
docker exec under-the-hood-worker cat $CDIR/cpu.weight $CDIR/cpu.max $CDIR/memory.max
```

```output
35
50000 100000
134217728
```

The same three numbers, now in the files the kernel enforces. These are the same kind of files you wrote by hand in module 01.

## Step 5: One process, two points of view

Find the container's process on the node, then look at it from inside the pod:

```bash
HPID=$(docker exec under-the-hood-worker head -n1 $CDIR/cgroup.procs)
docker exec under-the-hood-worker cat /proc/$HPID/comm /proc/$HPID/cgroup
kubectl -n lab exec follow-me -- cat /proc/1/comm /proc/self/cgroup
```

```output
sleep
0::/kubelet.slice/kubelet-kubepods.slice/kubelet-kubepods-burstable.slice/…/cri-containerd-<id>.scope
sleep
0::/
```

**What it means:** it's the same `sleep` process. On the node it has an ordinary PID and a long cgroup path. Inside the pod, the **PID namespace** makes it PID 1, and the **cgroup namespace** makes its cgroup look like the root, `/`. Namespaces change what the process *sees*; the cgroup still controls what it *gets*.

## Clean up

```bash
kubectl -n lab delete pod follow-me
```

## Summary

| Layer | What it holds | How you looked |
|---|---|---|
| API | `resources:` in the pod spec | `kubectl get pod` |
| Container runtime | OCI spec: shares, quota, period, memory limit | `crictl inspect` |
| systemd | A scope unit with CPUWeight, CPUQuotaPerSecUSec, MemoryMax | `systemctl show` |
| Kernel | `cpu.weight`, `cpu.max`, `memory.max` | `cat` under `/sys/fs/cgroup` |

## Shortcut

`make 02-follow-the-pod` runs every step and checks that each layer carries the same numbers.
