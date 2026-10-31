# 17 · Not all memory is equal

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 17](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#17-not-all-memory-is-equal)
>
> **You'll learn:** the difference between file cache and anonymous memory, the working set, and `memory.peak`: why a pod can be "at its limit" and fine, or killed while the graph said it had room.

## The question

How can a container be at 100% of its memory limit and perfectly healthy?

## Predict first

<details>
<summary>The container has a 128Mi limit, and you read 192 MiB of files through it. Is it OOM-killed?</summary>

No. File data sits in the page cache, which the kernel can drop and read again later. The cgroup hits its limit over and over, the kernel drops old cache, and nothing dies.
</details>

## Steps

`mem-lab` is an empty container with a 128Mi limit. First, look at it fresh:

```bash
kubectl apply -f labs/17-not-all-memory-is-equal/pod.yaml
kubectl wait --for=condition=Ready pod/mem-lab --timeout=120s
kubectl exec mem-lab -- cat /sys/fs/cgroup/memory.current
kubectl exec mem-lab -- grep -E '^(anon|file|inactive_file) ' /sys/fs/cgroup/memory.stat
```

**File cache.** Write and read 192 MiB of files inside it (`cache --mib 192`):

```bash
kubectl exec mem-lab -- cache --mib 192
kubectl exec mem-lab -- cat /sys/fs/cgroup/memory.current
kubectl exec mem-lab -- grep -E '^(anon|file|inactive_file) ' /sys/fs/cgroup/memory.stat
docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh mem-lab)/memory.events"
```

On my run: `memory.current` **125 MiB**, right at the 128Mi limit, of which **122 MiB was `file`** and **under 1 MiB `anon`**. The pod's `memory.events` shows `max` going up (the limit was hit and the kernel reclaimed cache) and `oom_kill 0`. At its limit, and fine. (We read the **pod's** `memory.events` from the node: the pod and the container have the same 128Mi limit, and the kernel counts these events on the pod's cgroup.)

**Anonymous memory.** Now allocate memory a program holds on to (`alloc`), inside the same container:

```bash
kubectl exec mem-lab -- alloc --mib 16 --every 100ms
echo "exit code: $?"
sleep 5
kubectl get pod mem-lab -o jsonpath='restarts={.status.containerStatuses[0].restartCount} reason={.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh mem-lab)/memory.events"
```

Exit code 137, a restart, and `oom_group_kill 1`: there was no cache left to drop, only memory a running program was holding.

**The peak the graph missed.** `memory.peak` remembers the highest usage since the cgroup was created, even between dashboard samples:

```bash
docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh mem-lab)/memory.peak"
```

## What happened

| Kind | In `memory.stat` | Can the kernel take it back? |
|---|---|---|
| Anonymous | `anon` | No, only by killing the program |
| File cache | `file` | Yes: drop it and reread from disk |

Both count towards `memory.current` and `memory.max`. That's why the kubelet and most dashboards use the **working set**, `memory.current − inactive_file` (the metric `container_memory_working_set_bytes`). After the file test: `memory.current` 125 MiB, working set about 1 MiB. And because dashboards sample every 15 to 60 seconds, a short spike can kill a pod without ever showing on a graph; `memory.peak` and `memory.events` don't miss it.

> **In one line:** file cache is counted but can be dropped; memory a program allocates can't, and that's what gets OOM-killed. Watch the working set, not `memory.current`.

Check your work: `make check LAB=17`

## Clean up

```bash
kubectl delete -f labs/17-not-all-memory-is-equal/ --ignore-not-found
```

**Next:** [lab 18 · Node pressure eviction](../18-node-pressure-eviction/) (needs `make cluster PROFILE=pressure`)
