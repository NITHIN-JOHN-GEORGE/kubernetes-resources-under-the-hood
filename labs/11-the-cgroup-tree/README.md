# 11 · Where every pod lives: the cgroup tree

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 11](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#11-where-every-pod-lives-the-cgroup-tree) and [chapter 18](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#qos-classes-who-is-most-protected)
>
> **You'll learn:** how the kubelet nests pods by QoS class, and how that class also decides who the kernel kills first when the whole node runs out.

## The question

Why is a container's cgroup buried so deep?

## Predict first

<details>
<summary>Three pods: requests equal to limits, requests lower than limits, and nothing set. Which one sits directly under the box for all pods?</summary>

The Guaranteed one. Burstable and BestEffort pods each get an extra box for their class; Guaranteed pods don't.
</details>

## Steps

```bash
kubectl apply -f labs/11-the-cgroup-tree/pods.yaml
kubectl wait --for=condition=Ready pod/qos-guaranteed pod/qos-burstable pod/qos-besteffort --timeout=120s
kubectl get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```

The box that holds every pod on the worker, and its ceiling:

```bash
docker exec under-the-hood-worker ls /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/
docker exec under-the-hood-worker cat /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/memory.max
```

You'll see `kubelet-kubepods-burstable.slice` and `kubelet-kubepods-besteffort.slice`, Guaranteed pods' own `…-pod<uid>.slice` folders, and a `memory.max` of about your node's memory (`8321515520` on mine: the most all pods together may use).

Where did each pod land?

```bash
for p in qos-guaranteed qos-burstable qos-besteffort; do echo "$p: $(./scripts/pod-cgroup.sh $p | sed 's#.*kubelet-kubepods.slice/##')"; done
```

The class also shows up on every process, as a number the kernel uses when the **whole machine** runs out of memory:

```bash
for p in qos-guaranteed qos-burstable qos-besteffort; do echo "$p $(kubectl exec $p -- cat /proc/1/oom_score_adj)"; done
```

```text
qos-guaranteed -997
qos-burstable 996
qos-besteffort 1000
```

## What happened

- The kubelet builds a tree: **all pods → QoS class → pod → container**. Anything in a box is also held to the limits of the boxes around it.
- On GKE, EKS and most clusters the tree starts at `/sys/fs/cgroup/kubepods.slice`. The `kubelet.slice/kubelet-` prefix is a kind detail.
- `oom_score_adj` runs from −1000 to 1000. When the machine is out of memory, the kernel kills the process with the highest score: BestEffort first, Guaranteed last. (Burstable's number depends on its memory request.)

> **In one line:** cgroups nest, a child is held to its parents' limits, and the QoS class decides both where a pod sits and how protected it is.

Check your work: `make check LAB=11`

## Clean up

```bash
kubectl delete -f labs/11-the-cgroup-tree/ --ignore-not-found
```

**Next:** [lab 12 · How Linux shares a CPU](../12-how-linux-shares-a-cpu/)
