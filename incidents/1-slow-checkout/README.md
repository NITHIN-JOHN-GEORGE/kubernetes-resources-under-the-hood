# Incident 1 · Checkout is slow

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 15 minutes · **Labs that help:** [14](../../labs/14-limits-and-throttling/), [15](../../labs/15-the-outage/)

## The ticket

> "Checkout takes almost a second. The target is under 100 ms. The CPU graph shows the pod under its limit, so it can't be CPU. Right?"

## Start

```sh
make incident-1
```

It walks you through three steps, pausing between each (press Enter to go on):

1. **The scene:** what `checkout-api` does, and its resources.
2. **What the on-call engineer sees:** the pod's average CPU, and how long requests take.
3. **The ticket**, and the places to look.

## Your turn

Find out why each request is so slow. Look at these, in order:

| # | Look at | Command |
|---|---|---|
| 1 | How the limit is written in the kernel. What does each number mean? | `kubectl exec checkout-api -- cat /sys/fs/cgroup/cpu.max` |
| 2 | Whether the kernel made the pod wait. Read it twice, a few seconds apart | `kubectl exec checkout-api -- cat /sys/fs/cgroup/cpu.stat` |
| 3 | Watch it live. Compare "used" with "throttled" | `./scripts/watch.sh checkout-api` |

Stuck? `make hint-1` gives one clue at a time. Run it again for the next.

## Check your answer

```sh
make answer-1 CAUSE=<one or two words>     # or CAUSE=show to skip to the answer
```

It shows the evidence from your cluster, explains why it happened step by step, applies the fix live (an in-place resize to 1 CPU) and compares requests before and after.

<details>
<summary>Spoiler: the answer</summary>

**CPU throttling.** Each request runs 4 processes at once, about 160 ms of CPU in total. The 200m limit is a 20 ms budget per 100 ms period, which 4 processes spend in about 5 ms; then the whole container waits for the next period. So a request takes about 8 periods, around 800 ms. The pod sleeps between requests, so its average CPU stays under the limit and the graph looks fine. Read more in [chapter 14 of the blog](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#14-cpu-limits-become-a-budget-throttling).
</details>

## Clean up

```sh
make reset
```

## What's in this folder

| File | What it is |
|---|---|
| `pod.yaml` | The `checkout-api` pod |
| `start.sh` | What `make incident-1` runs |
| `hint.md` | The clues, one per section |
| `answer.sh` | What `make answer-1` runs |
