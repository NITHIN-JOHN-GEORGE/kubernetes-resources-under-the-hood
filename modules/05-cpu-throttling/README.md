# 05 · CPU throttling

**What you'll learn:** what a CPU limit really does, and why a container can be slowed down even when the node has CPUs sitting idle.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Look at the two pods

Open [`pods.yaml`](pods.yaml). There are two pods, and both run the same thing: four loops that spin forever, each wanting a full CPU.

| Pod | CPU limit |
|---|---|
| `cpu-limited` | `200m` (a fifth of one CPU) |
| `cpu-unlimited` | none |

## Step 2: Start them

```bash
kubectl create namespace lab            # skip if it already exists
kubectl -n lab apply -f modules/05-cpu-throttling/pods.yaml
kubectl -n lab wait --for=condition=Ready pod/cpu-limited pod/cpu-unlimited
```

## Step 3: Compare their CPU limits

```bash
kubectl -n lab exec cpu-limited   -- cat /sys/fs/cgroup/cpu.max
kubectl -n lab exec cpu-unlimited -- cat /sys/fs/cgroup/cpu.max
```

```output
20000 100000
max 100000
```

**What `cpu.max` is:** two numbers, both in microseconds (millionths of a second).

- The second number is the **period**: the kernel hands out CPU time in windows of 100,000 µs, which is 100 milliseconds (the default).
- The first number is the **quota**: how much CPU time the container may use inside each window. `20000` means 20 ms. `max` means no limit.

So `20000 100000` reads as: "in every 100 ms, this container may run for 20 ms in total." That's `200m`.

The important part is **in total, across all its threads**. Four busy threads running on four CPUs at once burn through 20 ms in about 5 ms of real time. After that, any work in the group that's ready to run has to wait until the next window starts, about 95 ms later in this example. That waiting is called **throttling**.

## Step 4: Watch the throttling counter

The kernel counts all of this in `cpu.stat`. Read it, wait 10 seconds, and read it again:

```bash
kubectl -n lab exec cpu-limited -- cat /sys/fs/cgroup/cpu.stat
sleep 10
kubectl -n lab exec cpu-limited -- cat /sys/fs/cgroup/cpu.stat
```

You'll see something like this (only the lines that matter here; your numbers will differ):

```text
usage_usec 41203117
nr_periods 2051
nr_throttled 2049
throttled_usec 162874332
```

**What each line means:**

| Field | Meaning |
|---|---|
| `usage_usec` | Total CPU time the container has used, in microseconds |
| `nr_periods` | How many 100 ms windows have passed while it had work to do |
| `nr_throttled` | In how many of those windows it ran out of quota and had to wait |
| `throttled_usec` | Total time it spent frozen, waiting for the next window |

Between your two reads, `nr_periods` and `nr_throttled` should both go up by about 100 (10 seconds is 100 windows). Throttled in almost every window: that's a container that always wants more than its limit.

## Step 5: Check the other pod

```bash
kubectl -n lab exec cpu-unlimited -- cat /sys/fs/cgroup/cpu.stat
```

`nr_throttled` stays at `0`. Same loops, same node, no limit, so it simply uses the idle CPUs.

## What the shortcut measured

`make 05-cpu-throttling` does the same reads about 15 seconds apart and turns them into CPU used. A real run:

```text
  pod            periods          throttled      CPU used (millicores)
  cpu-limited    250              249            200
  cpu-unlimited  -                0              several thousand
```

## Why it matters in production

A service that does its work in short bursts, such as handling a request with several threads, can look like it's using 30% CPU on average but still be throttled in most windows. Every request that lands in one of those frozen gaps is slow. Watch the ratio of throttled windows, not average CPU:

```text
rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m])
```

## Clean up

```bash
kubectl -n lab delete pod cpu-limited cpu-unlimited
```

## Summary

| File | What it tells you |
|---|---|
| `cpu.max` | The CPU limit as "quota period" in microseconds. `max` means no limit |
| `cpu.stat` → `nr_throttled` | How many 100 ms windows the container was frozen in |
| `cpu.stat` → `throttled_usec` | How long it was frozen in total |

## Shortcut

`make 05-cpu-throttling` runs all of this and checks the results. Set `SAMPLE=30` to measure for longer.
