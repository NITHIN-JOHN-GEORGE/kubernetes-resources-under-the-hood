# Incident 3 · Pending, with memory to spare

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Labs that help:** [09](../../labs/09-four-checkpoints/), [18](../../labs/18-node-pressure-eviction/)

## The ticket

> "new-feature has been Pending for ages. The node is using a fraction of its memory. Is the scheduler broken?"

## Start

```sh
make incident-3
```

It walks you through three steps, pausing between each (press Enter to go on):

1. **The scene:** three nightly batch jobs and the new service, and what each requests.
2. **What the on-call engineer sees:** `new-feature` stuck in `Pending`, and how little memory the node is really using.
3. **The ticket**, and the places to look.

## Your turn

Find out why `new-feature` can't be placed. Look at these, in order:

| # | Look at | Command |
|---|---|---|
| 1 | What the scheduler said: the Events at the bottom | `kubectl describe pod new-feature \| tail -5` |
| 2 | What the node has promised, as opposed to what it uses | `kubectl describe node under-the-hood-worker \| grep -A6 "Allocated resources"` |
| 3 | Who the promises went to | `kubectl get pods -l incident -o custom-columns=NAME:.metadata.name,MEM_REQUEST:.spec.containers[0].resources.requests.memory` |

Stuck? `make hint-3` gives one clue at a time. Run it again for the next.

## Check your answer

```sh
make answer-3 CAUSE=<one or two words>     # or CAUSE=show to skip to the answer
```

It shows the evidence from your cluster, explains why it happened step by step, removes one idle batch job and shows `new-feature` get scheduled.

<details>
<summary>Spoiler: the answer</summary>

**The idle pods' memory requests.** The scheduler compares requests with the node's allocatable memory and never looks at real usage. The three sleeping batch jobs requested almost the whole node between them, so there wasn't 1 GiB left to promise to `new-feature`. "Insufficient memory" means "not enough left to promise", not "not enough free". Read more in [chapter 9 of the blog](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#9-the-four-checkpoints).
</details>

## Clean up

```sh
make reset
```

## What's in this folder

| File | What it is |
|---|---|
| `pods.yaml` | The three batch jobs and `new-feature` (`start.sh` fills in the batch jobs' memory requests to fit your node) |
| `start.sh` | What `make incident-3` runs |
| `hint.md` | The clues, one per section |
| `answer.sh` | What `make answer-3` runs |
