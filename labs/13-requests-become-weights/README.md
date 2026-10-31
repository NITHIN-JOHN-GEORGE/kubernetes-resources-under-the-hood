# 13 · CPU requests become weights

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 13](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#13-cpu-requests-become-weights)
>
> **You'll learn:** what a CPU request really buys you, how it becomes `cpu.weight`, and why the **pod's** weight is the one that decides the split.

## The question

What does a CPU request actually get you?

## Predict first

<details>
<summary>Same greedy pods as lab 12, but one requests 100m and the other 800m. How will they split the node?</summary>

The bigger request takes most of the CPU, close to the 8× ratio of the requests. Neither gets "its request" as a reservation; they share the node by weight.
</details>

## Steps

```bash
kubectl apply -f labs/13-requests-become-weights/pods.yaml
kubectl wait --for=condition=Ready pod/weight-low pod/weight-high --timeout=120s
kubectl exec weight-low  -- cat /sys/fs/cgroup/cpu.weight
kubectl exec weight-high -- cat /sys/fs/cgroup/cpu.weight
```

```text
17
84
```

Those are the **containers'** weights. Now measure the split over 10 seconds:

```bash
l1=$(kubectl exec weight-low  -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
h1=$(kubectl exec weight-high -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
sleep 10
l2=$(kubectl exec weight-low  -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
h2=$(kubectl exec weight-high -- awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
echo "weight-low: $(( (l2 - l1) / 10000 ))m   weight-high: $(( (h2 - h1) / 10000 ))m"
```

On my 10-CPU setup: **1013m vs 8966m, 8.8×**. That's close to 800 ÷ 100, but far from 84 ÷ 17 ≈ 4.9. Why? Each pod has one busy container, so the competition happens one level up, between the **pod** cgroups. Read their weights:

```bash
for p in weight-low weight-high; do echo "$p pod cgroup: $(docker exec under-the-hood-worker cat $(./scripts/pod-cgroup.sh $p)/cpu.weight)"; done
```

```text
weight-low pod cgroup: 4
weight-high pod cgroup: 32
```

32 ÷ 4 = 8.

## What happened

Your request goes through two conversions. The kubelet turns millicores into **CPU shares** (`millicores × 1024 / 1000`: 100m → 102, 800m → 819). Then shares become a cgroup v2 **weight**, and two different formulas are in use:

| Request | Shares | Old formula (pod cgroups here) | New formula (containers here) |
|---|---|---|---|
| 100m | 102 | **4** | **17** |
| 800m | 819 | **32** | **84** |

The kubelet sets the pod cgroup's weight with the old straight line, `1 + (shares − 2) × 9999 / 262142`. The runtime (runc 1.3.2+, crun 1.23+) sets the container's with a newer curve. Siblings compete with siblings: pods with pods, containers inside one pod with each other. So the pod weights decide how pods split a busy node.

> **In one line:** a CPU request is your share when CPUs are busy, and the pod cgroup's weight decides how pods split the node.

Check your work: `make check LAB=13`

## Clean up

```bash
kubectl delete -f labs/13-requests-become-weights/ --ignore-not-found
```

**Next:** [lab 14 · Limits and throttling](../14-limits-and-throttling/)
