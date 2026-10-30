# 05 · Your first look at cpu.max and cpu.weight

> **Runs on:** Docker only · **Time:** 5 minutes · **Blog:** [chapter 5](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#5-your-first-look-at-cpumax-and-cpuweight)
>
> **You'll learn:** how `--cpus=0.5 --memory=128m` turn into numbers in three files, and the difference between a budget and a share.

## The question

You started the container with `--cpus=0.5 --memory=128m`. Where did those numbers go?

## Predict first

<details>
<summary>What will <code>cpu.max</code> say for half a CPU?</summary>

<code>50000 100000</code>: at most 50 ms of CPU in every 100 ms window. Both numbers are in microseconds.
</details>

## Steps

```bash
docker run -d --name lab-box --cpus=0.5 --memory=128m ubuntu sleep infinity
```

```bash
docker exec lab-box ls /sys/fs/cgroup
docker exec lab-box cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.weight
```

```text
50000 100000
134217728
100
```

Which processes do these limits apply to?

```bash
docker exec lab-box cat /sys/fs/cgroup/cgroup.procs
```

You'll see `1` (the container's `sleep`) and one more PID: the `cat` you just ran, which joined the same cgroup.

## What happened

| File | Value | Means |
|---|---|---|
| `cpu.max` | `50000 100000` | A **budget**: 50 ms of CPU per 100 ms. That's `--cpus=0.5`. Use it up and you wait |
| `memory.max` | `134217728` | 128 × 1024 × 1024 bytes. That's `--memory=128m` |
| `cpu.weight` | `100` | A **share** (the default), only used when groups compete for CPU |
| `cgroup.procs` | PIDs | Who all of this applies to, every thread of every listed process |

> **In one line:** `cpu.max` is a budget per 100 ms, `cpu.weight` is a share when CPUs are busy, `memory.max` is a byte ceiling.

Check your work: `make check LAB=05`

## Clean up

```bash
docker rm -f lab-box
```

**Next:** [lab 06 · CPU waits, memory kills](../06-cpu-waits-memory-kills/)
