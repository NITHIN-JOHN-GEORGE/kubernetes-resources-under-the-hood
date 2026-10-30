# 07 · Memory, properly

**What you'll learn:** that not all memory is the same. Some of what a container "uses" is cached file data the kernel can throw away at any moment; some is memory the program asked for and can't give back. Only the second kind gets you OOM-killed, and the difference explains most confusing memory graphs.

**Time:** about 10 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Two kinds of memory

| Kind | In `memory.stat` | What it is | Can the kernel take it back? |
|---|---|---|---|
| **Anonymous** | `anon` | Memory a program asked for: variables, heap, buffers | No. Only by killing the program (or swapping) |
| **File cache** | `file` | Copies of file data the kernel keeps in memory so the next read is fast | Yes. It can just drop it and reread from disk |

Both count towards a cgroup's `memory.current`, and both count towards `memory.max`.

## Step 1: Start the pod and look

```bash
kubectl create namespace lab            # skip if it already exists
kubectl -n lab apply -f modules/07-memory-deep-dive/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/mem-lab
kubectl -n lab exec mem-lab -- cat /sys/fs/cgroup/memory.current
kubectl -n lab exec mem-lab -- grep -E '^(anon|file|inactive_file) ' /sys/fs/cgroup/memory.stat
```

**What these files are:**

- **`memory.current`**: everything the cgroup is using right now, in bytes.
- **`memory.stat`**: the breakdown. `anon` and `file` are the two kinds above. `inactive_file` is the part of the file cache that hasn't been used recently, so it's first in line to be dropped.

A fresh container uses very little of either.

## Step 2: Read more files than fit

`mem-lab` has a 128Mi limit. Write a 192 MiB file (in 16 MiB steps, saving each to disk as we go), then read it back twice:

```bash
kubectl -n lab exec mem-lab -- sh -c 'i=0; while [ $i -lt 12 ]; do dd if=/dev/zero of=/tmp/f bs=1M count=16 seek=$((i*16)) conv=notrunc,fsync 2>/dev/null; i=$((i+1)); done; cat /tmp/f > /dev/null; cat /tmp/f > /dev/null'
kubectl -n lab exec mem-lab -- cat /sys/fs/cgroup/memory.current
kubectl -n lab exec mem-lab -- grep -E '^(anon|file|inactive_file) ' /sys/fs/cgroup/memory.stat
```

You'll see `memory.current` close to the 128 MiB limit, almost all of it `file`, and only a little `anon`. The container is "at its limit", yet nothing went wrong.

Now look at the kernel's record:

```bash
POD_DIR=$(./scripts/pod-cgroup.sh mem-lab)
docker exec under-the-hood-worker cat $POD_DIR/memory.events
```

`max` is above zero (usage hit the limit) but `oom_kill` is `0`. Each time usage hit `memory.max`, the kernel **reclaimed** memory by dropping old file cache, and carried on.

**Why it matters:** many dashboards show `memory.current` (or something close to it). A service that reads lots of files will look like it's sitting at its limit all day, while being perfectly safe. That's why the kubelet and most Kubernetes dashboards use the **working set** instead:

```text
working set = memory.current - inactive_file
```

The working set leaves out the cache that's easy to drop, so it's a better guess at the memory the container really needs. It's the number behind `kubectl top` and the `container_memory_working_set_bytes` metric.

## Step 3: Allocate memory that can't be dropped

First, a setting the kubelet turns on for every container:

```bash
CDIR=$(docker exec under-the-hood-worker sh -c "ls -d $POD_DIR/cri-containerd-*.scope")
docker exec under-the-hood-worker cat $CDIR/memory.oom.group
```

```output
1
```

**What `memory.oom.group` is:** `1` means "if the kernel has to kill one process in this cgroup, kill all of them". So an OOM kill takes down the whole container rather than leaving it half-alive.

Now run a shell that keeps doubling a string, so its anonymous memory doubles every step:

```bash
kubectl -n lab exec mem-lab -- sh -c 'a=x; while :; do a=$a$a; done'
echo "exit code: $?"
docker exec under-the-hood-worker cat $POD_DIR/memory.events
kubectl -n lab get pod mem-lab
```

The command fails with exit code 137, `oom_kill` goes up, and the pod shows a restart. This time the kernel had nothing it could drop: the memory belonged to a running program, so the only way to stay under `memory.max` was to kill it, and because of `memory.oom.group`, the whole container went with it.

## What about `memory.high` and `memory.min`?

Two more files you'll see in every cgroup:

```bash
kubectl -n lab exec mem-lab -- cat /sys/fs/cgroup/memory.high /sys/fs/cgroup/memory.min
```

```output
max
0
```

- **`memory.high`** is a soft limit: above it, the kernel slows the cgroup down and reclaims hard, but doesn't kill. `max` means it isn't set.
- **`memory.min`** is memory the kernel protects for this cgroup even when the whole machine is short. `0` means no protection.

By default, Kubernetes sets neither. Clusters that turn on the `MemoryQoS` feature (still alpha) set `memory.min` from the memory request and `memory.high` a little below the limit, so pods slow down before they get killed.

## Clean up

```bash
kubectl -n lab delete pod mem-lab
```

## Summary

| File | Tells you |
|---|---|
| `memory.current` | Everything in use, including file cache |
| `memory.stat` → `anon` | Memory programs asked for. Can't be dropped |
| `memory.stat` → `file`, `inactive_file` | Cached file data. Can be dropped |
| `memory.events` → `max` | How often usage hit the limit and the kernel reclaimed |
| `memory.events` → `oom_kill` | How often reclaim wasn't enough and a process was killed |
| `memory.oom.group` | `1` = an OOM kill takes the whole container |
| `memory.high`, `memory.min` | Soft limit and protection. Not set by default |

## Shortcut

`make 07-memory-deep-dive` runs every step and checks each result.
