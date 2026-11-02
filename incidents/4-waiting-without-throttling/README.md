# Incident 4 · Waiting, but never throttled

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 15 minutes · **Labs that help:** [13](../../labs/13-requests-become-weights/), [14](../../labs/14-limits-and-throttling/), [19](../../labs/19-metrics-and-psi/)

## The ticket

> "The controller is slow and its 'CPU wait' is high, but it's never throttled. Its limit is way above what it uses. Is the node broken?"

## Start

```sh
make incident-4
```

It walks you through three steps, pausing between each (press Enter to go on):

1. **The scene:** what `controller` does, and the three batch jobs next to it.
2. **What the on-call engineer sees:** slow requests, and a throttling graph that stays at zero.
3. **The ticket**, and the places to look.

## Your turn

Find out what the controller is waiting for. Look at these, in order:

| # | Look at | Command |
|---|---|---|
| 1 | Is its own limit stopping it? Read it twice, a few seconds apart | `kubectl exec controller -- cat /sys/fs/cgroup/cpu.stat` |
| 2 | How much of the time its threads were ready, but waiting | `kubectl exec controller -- cat /sys/fs/cgroup/cpu.pressure` |
| 3 | The same, for the whole node | `docker exec under-the-hood-worker cat /proc/pressure/cpu` |
| 4 | Who it shares the node with, and what they asked for | `kubectl get pods -l incident -o custom-columns=NAME:.metadata.name,REQUEST:.spec.containers[0].resources.requests.cpu,LIMIT:.spec.containers[0].resources.limits.cpu` |

Stuck? `make hint-4` gives one clue at a time. Run it again for the next.

## Check your answer

```sh
make answer-4 CAUSE=<one or two words>     # or CAUSE=show to skip to the answer
```

It shows the three signals side by side, the neighbours' requests and limits against the node's size, the same signals as Prometheus metrics, then applies the fix live (shrinking the batch jobs with an in-place resize) and shows the waiting drop.

<details>
<summary>Spoiler: the answer</summary>

**Noisy neighbours.** The three batch jobs have CPU limits far above the node's size, so their wallets never empty and nothing is throttled. Their requests are tiny, so the scheduler packed them onto one node. Together they keep every core busy, and the controller's workers queue behind their threads: it has budget left but no free core. That waiting shows in the controller's `cpu.pressure`, but not in its `cpu.stat`, because it never ran out of its own budget. Read more in [Part 2 of the blog](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes-part-2/#waiting-for-cpu-your-limit-or-contention).
</details>

## Clean up

```sh
make reset
```

## What's in this folder

| File | What it is |
|---|---|
| `pods.yaml` | The `controller` pod and the three batch jobs |
| `start.sh` | What `make incident-4` runs |
| `hint.md` | The clues, one per section |
| `answer.sh` | What `make answer-4` runs |
