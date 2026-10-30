# 14 · CPU limits become a budget: throttling

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 14](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#14-cpu-limits-become-a-budget-throttling)
>
> **You'll learn:** how `cpu.max` works as a budget per 100 ms, why every thread spends the same budget, and how to see throttling in `cpu.stat`.

## The question

What happens when a container hits its CPU limit?

## Predict first

<details>
<summary><code>cpu-limited</code> runs 4 busy loops on a 200m limit. Out of the next 100 periods, in how many will it be throttled?</summary>

Nearly all 100. Four loops empty a 20 ms budget in about 5 ms of real time, then wait out the rest of every 100 ms period.
</details>

## Steps

Two pods, both running four busy loops. Only `cpu-limited` has a limit (200m):

```bash
kubectl apply -f labs/14-limits-and-throttling/pods.yaml
kubectl wait --for=condition=Ready pod/cpu-limited pod/cpu-unlimited --timeout=120s
kubectl exec cpu-limited   -- cat /sys/fs/cgroup/cpu.max
kubectl exec cpu-unlimited -- cat /sys/fs/cgroup/cpu.max
```

`20000 100000` (20 ms per 100 ms) for one, `max 100000` for the other. Read `cpu.stat` twice, 10 seconds apart:

```bash
kubectl exec cpu-limited -- cat /sys/fs/cgroup/cpu.stat
sleep 10
kubectl exec cpu-limited -- cat /sys/fs/cgroup/cpu.stat
kubectl exec cpu-unlimited -- grep nr_throttled /sys/fs/cgroup/cpu.stat
```

| Line in `cpu.stat` | Meaning |
|---|---|
| `usage_usec` | Total CPU time used, in microseconds |
| `nr_periods` | 100 ms periods in which the group had work to do |
| `nr_throttled` | Periods in which it ran out of budget and had to wait |
| `throttled_usec` | Total time spent waiting |

Between the two reads, `nr_periods` and `nr_throttled` both go up by about 100. Over a longer sample I measured 249 throttled out of 250 periods, at 200m of CPU. The unlimited pod's `nr_throttled` stays `0`.

**Watch it live** in a second terminal (Ctrl-C to stop). Every line names the file it came from:

```sh
./scripts/watch.sh cpu-limited
```

## What happened

`cpu.max` is a **wallet refilled every 100 ms**. Each CPU running one of the container's threads takes 5 ms slices from it. Four threads on four CPUs empty a 20 ms wallet in about 5 ms; after that *every* thread in the container waits for the next refill, even if the node has idle CPUs. The dashboard says "200m, at its limit", but every request that lands in those gaps is slow.

> **In one line:** a CPU limit never kills. It makes you wait, even on an idle node, and every thread in the container spends the same budget.

Check your work: `make check LAB=14`

## Clean up

```bash
kubectl delete -f labs/14-limits-and-throttling/ --ignore-not-found
```

**Next:** [lab 15 · The outage](../15-the-outage/)
