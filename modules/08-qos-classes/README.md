# 08 · QoS classes

**What you'll learn:** how Kubernetes sorts pods into three classes, where each class lives in the cgroup tree, and who the kernel kills first when the whole node runs out of memory.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Look at the three pods

Open [`pods.yaml`](pods.yaml). Three pods all run `sleep`. Only their `resources:` differ:

| Pod | Resources | Class it should get |
|---|---|---|
| `qos-guaranteed` | requests **equal** limits, for CPU and memory | Guaranteed |
| `qos-burstable` | some requests and limits, but not equal | Burstable |
| `qos-besteffort` | nothing at all | BestEffort |

You never pick the class yourself. Kubernetes works it out from these numbers.

## Step 2: Start them and see their class

```bash
kubectl create namespace lab            # skip if it already exists
kubectl -n lab apply -f modules/08-qos-classes/pods.yaml
kubectl -n lab wait --for=condition=Ready pod -l module=08
kubectl -n lab get pods -l module=08 -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```

```output
NAME             QOS
qos-besteffort   BestEffort
qos-burstable    Burstable
qos-guaranteed   Guaranteed
```

## Step 3: See their "kill me first" score

```bash
for p in qos-guaranteed qos-burstable qos-besteffort; do
  echo "$p $(kubectl -n lab exec $p -- cat /proc/1/oom_score_adj)"
done
```

```output
qos-guaranteed -997
qos-burstable 996
qos-besteffort 1000
```

**What `/proc` is:** like `/sys/fs/cgroup`, it's a window into the kernel rather than files on disk. Every running process has a folder there, named after its process ID.

**What `/proc/1` is:** inside a container, the first process (here, `sleep`) sees itself as process number 1. So `/proc/1/` is the container's main process.

**What `oom_score_adj` is:** a number from -1000 to 1000 that nudges the kernel's choice when the *whole machine* runs out of memory. The kernel gives every process a "badness" score, mostly based on how much memory it uses, then adds this number. The highest score is killed first.

Kubernetes sets it from the QoS class:

| Class | `oom_score_adj` | Meaning |
|---|---|---|
| Guaranteed | -997 | Almost never picked |
| Burstable | between 2 and 999 | Depends on the memory request: a bigger request means a lower number |
| BestEffort | 1000 | Picked first |

The Burstable pod got 996 because its memory request (32Mi) is tiny compared with the node's memory.

## Step 4: See where each class lives

```bash
for p in qos-guaranteed qos-burstable qos-besteffort; do
  echo "$p  $(./scripts/pod-cgroup.sh $p | sed 's#/sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/##')"
done
```

```output
qos-guaranteed  kubelet-kubepods-pod<uid>.slice
qos-burstable   kubelet-kubepods-burstable.slice/kubelet-kubepods-burstable-pod<uid>.slice
qos-besteffort  kubelet-kubepods-besteffort.slice/kubelet-kubepods-besteffort-pod<uid>.slice
```

**What it means:** Guaranteed pods get their own folder right under the box for all pods. Burstable and BestEffort pods are grouped into a box per class, so the kubelet can treat each class as a group.

## Two kinds of "out of memory"

It's worth being precise, because they behave differently:

- **One container hits its own limit** (module 06): the kernel kills a process inside that container. The QoS class doesn't matter.
- **The whole node runs out of memory:** first the kubelet tries to evict pods (module 10), BestEffort first. If memory runs out faster than the kubelet can react, the kernel picks a victim itself, using `oom_score_adj`. Again BestEffort goes first.

## Clean up

```bash
kubectl -n lab delete pod -l module=08
```

## Summary

| Class | Rule | `oom_score_adj` | Folder |
|---|---|---|---|
| Guaranteed | requests = limits for CPU and memory, in every container | -997 | directly under the pod tree |
| Burstable | some requests or limits | 2 to 999 | `…-burstable.slice/` |
| BestEffort | nothing set | 1000 | `…-besteffort.slice/` |

## Shortcut

`make 08-qos-classes` runs all of this and checks each class, score and folder.
