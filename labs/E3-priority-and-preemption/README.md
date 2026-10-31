# E3 · Priority and preemption

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 5 minutes · **Blog:** [cheat sheet](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#cheat-sheet)
>
> **You'll learn:** how a high-priority pod that doesn't fit gets room by pushing a lower-priority pod off the node.

## The question

When a node is full, does an important pod just wait?

## Predict first

<details>
<summary>A low-priority pod has taken nearly all the worker's free CPU. A high-priority pod asks for the same amount. What happens?</summary>

The scheduler removes the low-priority pod to make room (preemption), and the high-priority pod runs.
</details>

## Steps

Two priority classes, `lab-low` and `lab-high`:

```bash
kubectl apply -f labs/E3-priority-and-preemption/priorityclasses.yaml
kubectl get priorityclass
```

Both pods request almost all of the worker's unrequested CPU. `scripts/node-free.sh cpu` prints how much is left, in millicores; we keep 200m spare:

```bash
CPU=$(( $(./scripts/node-free.sh cpu) - 200 ))m
echo "each pod requests $CPU"
sed "s/__CPU__/$CPU/" labs/E3-priority-and-preemption/pod-low.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/prio-low --timeout=120s
sed "s/__CPU__/$CPU/" labs/E3-priority-and-preemption/pod-high.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/prio-high --timeout=120s
kubectl get pods prio-low prio-high
kubectl get events --field-selector involvedObject.name=prio-low -o custom-columns=REASON:.reason,MESSAGE:.message
```

```text
REASON      MESSAGE
Preempted   Preempted by pod 2cb1a068-... on node under-the-hood-worker
Killing     Stopping container main
```

## What happened

`prio-high` didn't fit. Instead of leaving it `Pending`, the scheduler looked for lower-priority pods it could remove to make room, found `prio-low`, and deleted it. Preemption uses **requests**, like all scheduling: it frees requested CPU, not used CPU.

> **In one line:** when a pod doesn't fit, a higher priority lets it push lower-priority pods off the node.

Check your work: `make check LAB=E3`

## Clean up

```bash
kubectl delete pod prio-low prio-high --ignore-not-found
kubectl delete -f labs/E3-priority-and-preemption/priorityclasses.yaml --ignore-not-found
```

**Next:** try the [incidents](../../incidents/).
