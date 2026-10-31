# 16 · Memory limits and the OOM killer

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 5 minutes · **Blog:** [chapter 16](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#16-memory-limits-and-the-oom-killer)
>
> **You'll learn:** what happens at `memory.max`, what `OOMKilled` and exit code 137 mean, and how to read `memory.events`.

## The question

What happens when a container reaches its memory limit?

## Predict first

<details>
<summary>A program grabs 10 MiB every 0.3 seconds against a 64Mi limit. How far does it get before it dies?</summary>

Not quite to 64. The program's own runtime (here, Python) lives in the same box and uses memory too, so it dies around 50 to 60 MiB.
</details>

## Steps

```bash
kubectl apply -f labs/16-memory-limits-and-oom/pod.yaml
sleep 20
kubectl get pod memory-hog
kubectl logs memory-hog --previous | tail -3
```

```text
allocated 40 MiB
allocated 50 MiB
allocated 60 MiB
```

The status flips to `OOMKilled`, Kubernetes restarts it, and it happens again. The kernel keeps its own tally:

```bash
kubectl get pod memory-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} exit={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh memory-hog)/memory.events"
```

| Line | Meaning |
|---|---|
| `max` | Times usage hit `memory.max` and the kernel had to reclaim |
| `oom` | Times reclaim wasn't enough |
| `oom_kill` | Processes the kernel killed |
| `oom_group_kill` | Times it killed a whole container at once |

## What happened

At `memory.max` the kernel first **reclaims**: it frees memory it can drop, like cached file data. `alloc` only holds memory it asked for, so there's nothing to drop, and the **OOM killer** ends it with `SIGKILL`: exit code 137 (128 + 9). No warning, no last log line. `oom_group_kill` appears because the kubelet sets `memory.oom.group = 1` on each container: if one process has to die, the whole container goes.

> **In one line:** at `memory.max` the kernel reclaims what it can first; if that isn't enough, it OOM-kills: exit code 137, no warning.

Check your work: `make check LAB=16`

## Clean up

```bash
kubectl delete -f labs/16-memory-limits-and-oom/ --ignore-not-found
```

**Next:** [lab 17 · Not all memory is equal](../17-not-all-memory-is-equal/)
