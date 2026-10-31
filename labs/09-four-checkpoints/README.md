# 09 · The four checkpoints

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 9](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#9-the-four-checkpoints)
>
> **You'll learn:** which part of Kubernetes stops a pod, and why "which checkpoint did this?" is the fastest way to debug resource problems.

## The question

What happens to your `resources:` block between `kubectl apply` and a running process?

## Predict first

<details>
<summary>Three pods: one over its namespace's quota, one asking for 1000 CPUs, one ordinary. Where does each one stop?</summary>

The first is refused by the **API server** and never exists. The second exists but stays <code>Pending</code>: the **scheduler** can't place it. The third is placed, the **kubelet** writes its cgroup files, and the **kernel** enforces them.
</details>

## Steps

**Checkpoint 1, the API server.** Create a namespace whose quota allows 100m of CPU requests, then try a pod that asks for 250m:

```bash
kubectl apply -f labs/09-four-checkpoints/quota.yaml
sleep 2
kubectl apply -f labs/09-four-checkpoints/pod-over-quota.yaml
```

You get `Error from server (Forbidden): … exceeded quota: tiny`. The pod was never created.

**Checkpoint 2, the scheduler.** A pod that asks for 1000 CPUs is accepted, but no node can take it:

```bash
kubectl apply -f labs/09-four-checkpoints/pod-too-big.yaml
sleep 3
kubectl get pod too-big
kubectl get events --field-selector involvedObject.name=too-big -o custom-columns=REASON:.reason,MESSAGE:.message
```

`Pending`, with `FailedScheduling … Insufficient cpu`. The scheduler compares **requests** with each node's allocatable CPU; it never looks at real usage.

**Checkpoints 3 and 4, the kubelet and the kernel.** An ordinary pod gets a node, the kubelet writes its numbers into cgroup files, and the kernel enforces them:

```bash
kubectl apply -f labs/09-four-checkpoints/pod-ok.yaml
kubectl wait --for=condition=Ready pod/pod-ok --timeout=120s
./scripts/pod-cgroup.sh pod-ok
kubectl exec pod-ok -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
```

The first line is the pod's cgroup folder on the node (the kubelet made it). The last two are the limits the kernel enforces: `50000 100000` and `134217728`.

## What happened

| Checkpoint | Decides | What stopped here |
|---|---|---|
| 1. API server | Is this pod allowed to exist? (quota, LimitRange, priority) | `over-quota` |
| 2. Scheduler | Which node has room for its **requests**? | `too-big` |
| 3. Kubelet | Writes the cgroup files, evicts when the node runs short | |
| 4. Kernel | Enforces the files: throttling and OOM kills | |

> **In one line:** Kubernetes decides and configures; the kernel enforces.

Check your work: `make check LAB=09`

## Clean up

```bash
kubectl delete -f labs/09-four-checkpoints/ --ignore-not-found
```

**Next:** [lab 10 · Follow one pod down to the kernel](../10-follow-one-pod-down/)
