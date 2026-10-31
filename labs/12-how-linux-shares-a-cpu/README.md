# 12 · How Linux shares a CPU

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 5 minutes · **Blog:** [chapter 12](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#12-how-linux-shares-a-cpu)
>
> **You'll learn:** what the kernel does when more threads want to run than there are CPUs.

## The question

Two pods each want every CPU on the node, and neither has a CPU limit. Who wins?

## Predict first

<details>
<summary>Both pods request 250m. How will the node's CPU be split between them?</summary>

About evenly. The kernel gives the next turn to whoever has had the least CPU, scaled by weight. Equal requests mean equal weights, so each pod gets about half the node.
</details>

## Steps

Each pod runs one busy loop per CPU on the node (`burn --threads all`), so together they want twice what exists:

```bash
kubectl apply -f labs/12-how-linux-shares-a-cpu/pods.yaml
kubectl wait --for=condition=Ready pod/share-a pod/share-b --timeout=120s
kubectl exec share-a -- cat /sys/fs/cgroup/cpu.weight /sys/fs/cgroup/cpu.max
kubectl exec share-b -- cat /sys/fs/cgroup/cpu.weight /sys/fs/cgroup/cpu.max
```

Same weight, and `max` means no CPU limit. Now measure how much CPU each one gets over 10 seconds (`usage_usec` is CPU time in microseconds; the difference ÷ 10,000 is millicores):

```bash
a1=$(kubectl exec share-a -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
b1=$(kubectl exec share-b -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
sleep 10
a2=$(kubectl exec share-a -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
b2=$(kubectl exec share-b -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
echo "share-a: $(( (a2 - a1) / 10000 ))m   share-b: $(( (b2 - b1) / 10000 ))m"
```

## What happened

Each pod got about half the node. The scheduler keeps a running tally of CPU time for every thread, and for every cgroup, and gives the next turn to whoever has had the least. Weight changes how fast that tally fills up; with equal weights, the split is even. Nobody is throttled, because nobody has a limit.

> **In one line:** the kernel gives the next turn to whoever has had the least CPU, and weight makes your tally fill more slowly.

Check your work: `make check LAB=12`

## Clean up

```bash
kubectl delete -f labs/12-how-linux-shares-a-cpu/ --ignore-not-found
```

**Next:** [lab 13 · CPU requests become weights](../13-requests-become-weights/)
