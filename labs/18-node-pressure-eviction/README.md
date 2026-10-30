# 18 · When the whole node runs short

> **Runs on:** the kind cluster with the pressure profile: `make clean && make cluster PROFILE=pressure` · **Time:** 10 minutes · **Blog:** [chapter 18](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#18-when-the-whole-node-runs-short)
>
> **You'll learn:** what allocatable is, and how the kubelet picks a pod to evict when the node runs low on memory, before the kernel has to.

## The question

Who gets removed when a node runs low on memory?

## Predict first

<details>
<summary>A memory hog with no request runs next to two small, well-behaved pods. The node gets low on memory. Who goes?</summary>

The hog. The kubelet ranks pods by whether they use more than they requested, then priority, then by how far over their request they are. The hog uses hundreds of MiB against a request of 0.
</details>

## Steps

This profile makes the kubelet treat the node as "low on memory" once less than 75% of its memory is available (normally the threshold is 100Mi). That lets a small hog trigger eviction in under a minute, without editing anything live. Check it took effect:

```bash
docker exec under-the-hood-worker grep -A4 evictionHard /var/lib/kubelet/config.yaml
```

**Not all of a node is for pods.** What the node has, and what pods may request:

```bash
kubectl get node under-the-hood-worker -o jsonpath='{.status.capacity.memory}{"  capacity\n"}{.status.allocatable.memory}{"  allocatable\n"}'
```

```text
8126480Ki  capacity
2031620Ki  allocatable
```

Allocatable is capacity minus what the kubelet holds back: `systemReserved` (for the OS), `kubeReserved` (for the kubelet and runtime) and the `evictionHard` threshold. kind reserves nothing for the first two, so here the whole difference is this profile's 75% threshold. On a default kind cluster it's only the usual 100Mi; on GKE or EKS it's typically several hundred MiB or more.

**Eviction.** Start the hog and the two calm pods, and wait:

```bash
kubectl apply -f labs/18-node-pressure-eviction/pods.yaml
for i in $(seq 30); do
  [ "$(kubectl get pod memory-hog -o jsonpath='{.status.reason}')" = Evicted ] && break
  sleep 5
done
kubectl get pods
kubectl get pod memory-hog -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
```

`Evicted`, with a message that names the threshold, how much memory was available, and how much the hog was using against a request of 0. The two calm pods keep running.

## What happened

| | OOM kill (labs 16, 17) | Eviction (here) |
|---|---|---|
| **Who does it** | The kernel | The kubelet |
| **Trigger** | One cgroup hits its own `memory.max` | The whole node gets low on memory |
| **What you see** | `OOMKilled`, exit 137, container restarts | `Evicted`, pod `Failed`, not restarted here |
| **Who is chosen** | A process in that cgroup | Ranked by usage vs request, then priority |

The kubelet checks `memory.available` (node memory minus the node's working set) about every 10 seconds. Below the threshold it marks the node `MemoryPressure` and evicts. The kernel's machine-wide OOM killer is only the last resort.

> **In one line:** when the whole node runs short, the kubelet evicts first and the kernel kills last; pods using more than they requested go first.

Check your work: `make check LAB=18`

## Clean up

```bash
kubectl delete -f labs/18-node-pressure-eviction/ --ignore-not-found
```

Go back to the default cluster when you're done: `make clean && make cluster`.

**Next:** [lab 19 · Metrics and pressure (PSI)](../19-metrics-and-psi/)
