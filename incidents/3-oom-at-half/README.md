# Incident 3 · OOMKilled at half the limit

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 15 minutes · **Labs that help:** [16](../../labs/16-memory-limits-and-oom/), [17](../../labs/17-not-all-memory-is-equal/)

## The ticket

> "report-worker keeps restarting with OOMKilled. But the dashboard never shows it above about half its memory limit. Is the OOM killer broken?"

## Start

```sh
make incident-3
```

It walks you through three steps, pausing between each (press Enter to go on):

1. **The scene:** what `report-worker` does, and its resources.
2. **What the on-call engineer sees:** its memory sampled every 15 seconds, like a metrics scraper, and the restart count.
3. **The ticket**, and the places to look.

## Your turn

Find out what uses the memory when it dies. Look at these, in order:

| # | Look at | Command |
|---|---|---|
| 1 | How it died: the reason and exit code under "Last State" | `kubectl describe pod report-worker \| grep -A4 "Last State"` |
| 2 | What it was doing just before each restart | `kubectl logs report-worker` |
| 3 | What the kernel remembers: compare `memory.peak` with the 256Mi limit (268435456) | `POD_DIR=$(./scripts/pod-cgroup.sh report-worker)`<br>`docker exec under-the-hood-worker cat $POD_DIR/memory.peak $POD_DIR/memory.events` |

Stuck? `make hint-3` gives one clue at a time. Run it again for the next.

## Check your answer

```sh
make answer-3 CAUSE=<one or two words>     # or CAUSE=show to skip to the answer
```

It shows the evidence from your cluster, explains why it happened step by step, raises the memory limit live to 320Mi and shows the restarts stop.

<details>
<summary>Spoiler: the answer</summary>

**A short memory spike between dashboard samples.** The worker keeps a 100 MiB cache, the "about 40%" on the graph. Every 20 seconds it builds a report that needs another 200 MiB for well under a second, which goes past the 256 MiB limit, so the kernel OOM-kills it. A dashboard sampling every 15 seconds almost never catches the spike; `memory.peak` and `memory.events` do, because the kernel counts rather than samples. Read more in [chapter 17 of the blog](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#17-not-all-memory-is-equal).
</details>

## Clean up

```sh
make reset
```

## What's in this folder

| File | What it is |
|---|---|
| `pod.yaml` | The `report-worker` pod |
| `start.sh` | What `make incident-3` runs |
| `hint.md` | The clues, one per section |
| `answer.sh` | What `make answer-3` runs |
