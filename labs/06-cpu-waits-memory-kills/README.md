# 06 · CPU waits, memory kills

> **Runs on:** Docker only · **Time:** 5 minutes · **Blog:** [chapter 6](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#6-why-cpu-limits-slow-you-down-but-memory-limits-kill-you)
>
> **You'll learn:** why a CPU limit makes a program slow, while a memory limit makes it crash.

## The question

Two containers go over their limits: one on CPU, one on memory. What happens to each?

## Predict first

<details>
<summary>Four busy loops get a fifth of a CPU. A program that keeps grabbing memory gets 64 MiB. Which one dies?</summary>

Only the memory one. CPU is time, so the kernel can make the loops wait their turn. Memory is space: once it's full and nothing can be freed, the kernel has to kill a process.
</details>

## Steps

These steps use the `lab-tools` image (`make image`, from lab 01).

**CPU.** Four busy loops (`burn --threads 4`) with a fifth of a CPU:

```bash
docker run -d --name lab-cpu --cpus=0.2 lab-tools:1.0 burn --threads 4
sleep 5
docker exec lab-cpu grep -E 'nr_periods|nr_throttled' /sys/fs/cgroup/cpu.stat
sleep 5
docker exec lab-cpu grep -E 'nr_periods|nr_throttled' /sys/fs/cgroup/cpu.stat
docker ps --filter name=lab-cpu --format '{{.Names}}: {{.Status}}'
```

`nr_periods` counts 100 ms windows; `nr_throttled` counts the ones where the loops used up their budget and had to wait. Both climb by about 50 in 5 seconds, and the container is still `Up`.

**Memory.** A program that grabs 10 MiB every 0.3 seconds and never lets go (`alloc`), with a 64 MiB limit and no swap:

```bash
docker run --name lab-mem --memory=64m --memory-swap=64m lab-tools:1.0 alloc --mib 10 --every 300ms
echo "exit code: $?"
docker inspect lab-mem --format 'OOMKilled={{.State.OOMKilled}}'
```

It prints a few `allocated … MiB` lines, then stops: exit code **137**, `OOMKilled=true`.

## What happened

- **CPU is time.** When the loops spend their 20 ms, the kernel pauses them until the next 100 ms window. They run slower and stay alive. That's **throttling**.
- **Memory is space.** At the limit, the kernel first tries to free memory it can drop (cached file data). `alloc` holds only memory it asked for, so nothing can be dropped, and the kernel kills it. Exit code 137 = 128 + 9, signal 9 being `SIGKILL`.

> **In one line:** CPU can be delayed, so CPU limits cause waiting. Memory can't, so memory limits end in OOM kills.

Check your work: `make check LAB=06`

## Clean up

```bash
docker rm -f lab-cpu lab-mem
```

**Next:** [lab 07 · What a container is](../07-what-is-a-container/)
