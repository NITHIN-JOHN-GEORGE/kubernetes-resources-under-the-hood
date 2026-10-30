# 03 · /proc: what every process is doing right now

> **Runs on:** Docker only · **Time:** 5 minutes · **Blog:** [chapter 3](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#3-proc-what-every-process-is-doing-right-now)
>
> **You'll learn:** how to read a process's name, threads, memory and cgroup straight from the kernel.

## The question

Where do `ps` and `top` get their numbers?

## Predict first

<details>
<summary>Every process belongs to a cgroup, and <code>/proc/self/cgroup</code> says which. Inside a container, what do you expect it to print?</summary>

Just <code>0::/</code>, as if the container were at the top of the tree. Lab 07 shows why: the cgroup namespace hides the real, much longer path.
</details>

## Steps

```bash
docker run -d --name lab-box --cpus=0.5 --memory=128m ubuntu sleep infinity
```

`/proc` has one folder per process, named after its PID:

```bash
docker exec lab-box ls /proc
```

`/proc/self` always means "the process reading this". Ask about the `cat` and `grep` you run:

```bash
docker exec lab-box cat /proc/self/comm
docker exec lab-box grep Threads /proc/self/status
docker exec lab-box grep VmRSS /proc/self/status
docker exec lab-box cat /proc/self/cgroup
```

```text
cat
Threads:	1
VmRSS:	    1544 kB
0::/
```

| File | What the kernel tells you |
|---|---|
| `/proc/<pid>/comm` | The process's name |
| `/proc/<pid>/status` | Its state, thread count, memory use |
| `/proc/<pid>/task/` | One folder per thread |
| `/proc/<pid>/cgroup` | Which cgroup it belongs to |

## What happened

`/proc` is the kernel's live report on processes. `ps`, `top` and `free` have no secret access: they read these files. And every process has a line saying which **cgroup** it's in, which is where its limits come from.

> **In one line:** `/proc` is a live report on every process, including which cgroup it lives in.

Check your work: `make check LAB=03`

## Clean up

```bash
docker rm -f lab-box
```

**Next:** [lab 04 · /sys and /sys/fs/cgroup](../04-sys-and-sys-fs-cgroup/)
