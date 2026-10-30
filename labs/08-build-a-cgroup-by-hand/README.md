# 08 · Build a cgroup by hand

> **Runs on:** the kind cluster (`make cluster`), used as a plain Linux machine · **Time:** 10 minutes · **Blog:** [chapter 8](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#8-build-a-cgroup-by-hand)
>
> **You'll learn:** that a cgroup is a folder, its files are dials, and a process joins it by writing its PID into `cgroup.procs`. Exactly what a container runtime does.

## The question

If cgroups are just files, can we make one ourselves?

## Predict first

<details>
<summary>A loop that wants a whole CPU goes into a box allowed a fifth of one. Does the kernel slow it down or kill it?</summary>

It slows it down: about 200m of CPU, throttled in nearly every 100 ms period, and never killed. A memory box is different: the second half of this lab ends in an OOM kill.
</details>

## Steps

We use the worker node, `under-the-hood-worker`, as a plain Linux machine. No pods are involved. (A kind node is a Docker container, and unlike lab 04's container it may write to `/sys/fs/cgroup`.)

**1. Make the box.** A cgroup is a folder. The kernel fills it with control files the moment it exists:

```bash
docker exec under-the-hood-worker mkdir /sys/fs/cgroup/lab-cpu
docker exec under-the-hood-worker ls /sys/fs/cgroup/lab-cpu
```

**2. Set a dial.** 20 ms of CPU in every 100 ms, a fifth of one CPU:

```bash
docker exec under-the-hood-worker sh -c 'echo "20000 100000" > /sys/fs/cgroup/lab-cpu/cpu.max'
```

**3. Put a process in.** A shell moves itself into the box (`$$` is its own PID), then spins forever:

```bash
docker exec -d under-the-hood-worker sh -c 'echo $$ > /sys/fs/cgroup/lab-cpu/cgroup.procs; while :; do :; done'
sleep 1
docker exec under-the-hood-worker cat /sys/fs/cgroup/lab-cpu/cgroup.procs
```

**4. Watch the kernel enforce it.** Read `cpu.stat` twice, five seconds apart:

```bash
docker exec under-the-hood-worker grep -E 'usage_usec|nr_throttled' /sys/fs/cgroup/lab-cpu/cpu.stat
sleep 5
docker exec under-the-hood-worker grep -E 'usage_usec|nr_throttled' /sys/fs/cgroup/lab-cpu/cpu.stat
```

`usage_usec` grows by about 1,000,000 (one second of CPU in five seconds: 20%), and `nr_throttled` by about 50. On my machine: **203m of CPU and 51 throttled periods in 5 seconds**.

**5. Change the dial while it runs.** No restart, no API call:

```bash
docker exec under-the-hood-worker sh -c 'echo "50000 100000" > /sys/fs/cgroup/lab-cpu/cpu.max'
sleep 5
docker exec under-the-hood-worker grep usage_usec /sys/fs/cgroup/lab-cpu/cpu.stat
```

Usage now climbs by about 2,500,000 every five seconds: half a CPU (I measured 512m).

**6. A memory box.** 50 MiB, no swap, and a shell that keeps doubling a string:

```bash
docker exec under-the-hood-worker sh -c 'mkdir /sys/fs/cgroup/lab-mem && echo 50M > /sys/fs/cgroup/lab-mem/memory.max'
docker exec under-the-hood-worker sh -c 'echo 0 > /sys/fs/cgroup/lab-mem/memory.swap.max' 2>/dev/null
docker exec under-the-hood-worker sh -c 'echo $$ > /sys/fs/cgroup/lab-mem/cgroup.procs; a=x; while :; do a=$a$a; done'
echo "exit code: $?"
docker exec under-the-hood-worker cat /sys/fs/cgroup/lab-mem/memory.events
```

```text
exit code: 137
low 0
high 0
max 35
oom 1
oom_kill 1
oom_group_kill 0
```

The limit was hit 35 times, reclaim failed once, and the kernel killed the process. An OOM kill, with no Kubernetes anywhere.

## What happened

Four steps are the whole idea, and every container runtime does them for every container: **mkdir** the cgroup, **echo** the limits into its files, **write the PID** into `cgroup.procs`, and the kernel enforces it from then on.

> **In one line:** a cgroup is a folder. Its files are dials the kernel enforces, and a process joins it by writing its PID into `cgroup.procs`.

Check your work: `make check LAB=08`

## Clean up

A cgroup is removed like an empty folder, once its processes are gone:

```bash
docker exec under-the-hood-worker sh -c 'kill -9 $(cat /sys/fs/cgroup/lab-cpu/cgroup.procs); sleep 1; rmdir /sys/fs/cgroup/lab-cpu /sys/fs/cgroup/lab-mem'
```

**Next:** [lab 09 · The four checkpoints](../09-four-checkpoints/)
