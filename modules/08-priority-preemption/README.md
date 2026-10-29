# 08 · Priority classes and preemption

**What you'll learn:** how to mark some pods as more important than others, and what happens when an important pod can't find room.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Create two priority levels

```bash
kubectl apply -f modules/08-priority-preemption/priorityclasses.yaml
kubectl get priorityclass
```

```output
NAME                      VALUE        GLOBAL-DEFAULT
lab-high                  1000000      false
lab-low                   1000         false
system-cluster-critical   2000000000   false
system-node-critical      2000001000   false
```

**What a PriorityClass is:** just a name with a number. Pods refer to it by name (`priorityClassName: lab-high`), and a bigger number means more important. The two `system-` ones come with every cluster and are used by Kubernetes' own critical pods.

## Step 2: Find out how much CPU is free

```bash
kubectl describe node under-the-hood-worker | grep -A5 "Allocated resources"
```

You'll see something like:

```text
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests    Limits
  --------           --------    ------
  cpu                100m (1%)   100m (1%)
```

Allocatable CPU on this node was 10 (10,000m), and 100m is already requested, so 9,900m is free. Work out yours the same way, then take away another 100m to leave a little gap:

```bash
CPU=9800m     # replace with: allocatable - requested - 100m
```

## Step 3: Fill the node with a low-priority pod

```bash
kubectl create namespace lab            # skip if it already exists
sed "s/__CPU__/$CPU/" modules/08-priority-preemption/pod-low.yaml | kubectl -n lab apply -f -
kubectl -n lab wait --for=condition=Ready pod/prio-low
```

`prio-low` now *requests* almost all the node's CPU. It doesn't use it, it just sleeps, but as far as the scheduler is concerned the node is full.

## Step 4: Send in the high-priority pod

```bash
sed "s/__CPU__/$CPU/" modules/08-priority-preemption/pod-high.yaml | kubectl -n lab apply -f -
kubectl -n lab get pods -l module=08 -w
```

Within a few seconds `prio-low` goes away and `prio-high` starts. Press Ctrl-C, then look at why:

```bash
kubectl -n lab get events --field-selector involvedObject.name=prio-low
```

```output
REASON      MESSAGE
Preempted   Preempted by pod 2cb1a068-... on node under-the-hood-worker
Killing     Stopping container main
```

**What happened:** `prio-high` didn't fit. Instead of leaving it `Pending`, the scheduler looked for lower-priority pods it could remove to make room, found `prio-low`, and deleted it. This is called **preemption**.

## Things worth knowing

- Priority is copied onto the pod when it's created (`kubectl get pod prio-high -o jsonpath='{.spec.priority}'` shows `1000000`). Changing the class later doesn't change existing pods.
- Higher-priority pods are also tried first when several are waiting to be scheduled.
- Priority also matters for eviction (module 07): among pods using more than their requests, lower priority goes first.
- `preemptionPolicy: Never` lets a pod jump the queue without pushing anyone out.
- No cgroup file is involved. This is all decided by the scheduler.

## Clean up

```bash
kubectl -n lab delete pod -l module=08
kubectl delete priorityclass lab-low lab-high
```

## Shortcut

`make 08-priority-preemption` works out the free CPU for you, runs both pods and checks the preemption happened.
