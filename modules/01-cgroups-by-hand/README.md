# 01 · Build a cgroup by hand

**What you'll learn:** what a cgroup is, by making two of them yourself with nothing but `mkdir`, `echo` and `cat`. No Kubernetes, no pods. Once you've done this, everything Kubernetes does with resources will look familiar.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster` (we only use its worker node as a Linux machine). Run every command from the repo folder.

---

## Step 1: See which controllers are available

```bash
docker exec under-the-hood-worker cat /sys/fs/cgroup/cgroup.subtree_control
```

```output
cpuset cpu io memory hugetlb pids rdma misc
```

(Your list may differ slightly.) `cgroup.subtree_control` says which controllers a cgroup hands down to the cgroups you create inside it. `cpu` and `memory` must be listed for the next steps to work.

## Step 2: Create a cgroup

```bash
docker exec under-the-hood-worker mkdir /sys/fs/cgroup/lab-cpu
docker exec under-the-hood-worker ls /sys/fs/cgroup/lab-cpu
```

That's it: a cgroup is a folder. The kernel immediately fills it with control files like `cpu.max`, `cpu.stat`, `memory.max` and `cgroup.procs`. You never create those files yourself.

## Step 3: Give it a CPU limit

```bash
docker exec under-the-hood-worker sh -c 'echo "20000 100000" > /sys/fs/cgroup/lab-cpu/cpu.max'
docker exec under-the-hood-worker cat /sys/fs/cgroup/lab-cpu/cpu.max
```

```output
20000 100000
```

"20,000 microseconds of CPU time in every 100,000 microseconds": 20 ms per 100 ms, a fifth of one CPU. In Kubernetes terms, `limits.cpu: 200m`.

## Step 4: Put a process in it

Start a shell that spins forever, and make it move itself into the cgroup first:

```bash
docker exec -d under-the-hood-worker sh -c 'echo $$ > /sys/fs/cgroup/lab-cpu/cgroup.procs; while :; do :; done'
docker exec under-the-hood-worker cat /sys/fs/cgroup/lab-cpu/cgroup.procs
```

`$$` is the shell's own PID. **Writing a PID into `cgroup.procs` is how a process joins a cgroup.** There's no other way, and it's exactly what a container runtime does for every container.

## Step 5: Watch the kernel hold it back

Read `usage_usec` (total CPU time used, in microseconds) twice, 5 seconds apart:

```bash
docker exec under-the-hood-worker grep -E 'usage_usec|nr_throttled' /sys/fs/cgroup/lab-cpu/cpu.stat
sleep 5
docker exec under-the-hood-worker grep -E 'usage_usec|nr_throttled' /sys/fs/cgroup/lab-cpu/cpu.stat
```

`usage_usec` goes up by about 1,000,000 (one second of CPU in five seconds, so 20%), and `nr_throttled` by about 50 (one per 100 ms window). The loop wants a whole CPU; the kernel gives it a fifth.

## Step 6: Change the limit while it runs

```bash
docker exec under-the-hood-worker sh -c 'echo "50000 100000" > /sys/fs/cgroup/lab-cpu/cpu.max'
```

Repeat step 5: usage now goes up by about 2,500,000 per 5 seconds (half a CPU). No restart, no API: the kernel just reads the new number. This is all Kubernetes' in-place resize does (module 13).

## Step 7: A memory limit

```bash
docker exec under-the-hood-worker sh -c 'mkdir /sys/fs/cgroup/lab-mem && echo 50M > /sys/fs/cgroup/lab-mem/memory.max'
docker exec under-the-hood-worker sh -c 'echo 0 > /sys/fs/cgroup/lab-mem/memory.swap.max' 2>/dev/null
docker exec under-the-hood-worker sh -c 'echo $$ > /sys/fs/cgroup/lab-mem/cgroup.procs; a=x; while :; do a=$a$a; done'
echo "exit code: $?"
docker exec under-the-hood-worker cat /sys/fs/cgroup/lab-mem/memory.events
```

The last-but-one command runs a shell that keeps doubling a string, so its memory use doubles every step. The `memory.swap.max` line turns off swap for this cgroup, so the kernel can't dodge the limit by moving memory to disk. Within a second the shell is gone:

```output
exit code: 137
low 0
high 0
max 3
oom 1
oom_kill 1
oom_group_kill 0
```

(Your `max` count may differ.) Exit code 137 means "killed by signal 9", and `oom_kill 1` is the kernel's own record of it. That's an OOM kill, with no Kubernetes anywhere.

## Clean up

```bash
docker exec under-the-hood-worker sh -c 'kill -9 $(cat /sys/fs/cgroup/lab-cpu/cgroup.procs); sleep 1; rmdir /sys/fs/cgroup/lab-cpu /sys/fs/cgroup/lab-mem'
```

A cgroup is removed with `rmdir`, and only once it has no processes left. You can't `rm` the files inside it.

## Summary

| You did | What it means |
|---|---|
| `mkdir` under `/sys/fs/cgroup` | Created a cgroup |
| `echo ... > cpu.max` | Set a CPU limit: quota and period, in microseconds |
| `echo PID > cgroup.procs` | Moved a process into the cgroup |
| read `cpu.stat` | Saw how much CPU it used and how often it was throttled |
| `echo ... > memory.max` | Set a memory limit, in bytes (`50M` works too) |
| read `memory.events` | Saw the kernel's record of OOM kills |

Everything Kubernetes does with CPU and memory comes down to these same files. Module 02 shows the kubelet and container runtime doing exactly this for a pod.

## Shortcut

`make 01-cgroups-by-hand` runs every step, checks the results and cleans up.
