# 07 · Node-pressure eviction

**What you'll learn:** what the kubelet does when a *node* (not one container) runs low on memory, and how it picks which pod to remove.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

> [!WARNING]
> This module needs a node that's actually short on memory, which your laptop isn't. So it **temporarily changes the worker's kubelet config** to make "low memory" kick in much sooner. Use the `make` command below for that part; it always puts the original config back, even if you press Ctrl-C. You'll do the looking around by hand.

---

## Step 1: Look at the node's memory health

```bash
kubectl get node under-the-hood-worker -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
```

```output
MemoryPressure=False
DiskPressure=False
PIDPressure=False
Ready=True
```

**What it means:** the kubelet constantly reports how the node is doing. `MemoryPressure=True` means free memory has dropped below the eviction threshold, and the kubelet has started removing pods.

## Step 2: Understand how the kubelet measures "free"

Every 10 seconds or so, the kubelet works out:

```text
memory.available = node capacity - working set
working set      = memory in use - memory the kernel could easily drop (inactive file cache)
```

If `memory.available` drops below `evictionHard` (by default 100Mi on most clusters), it picks a pod and evicts it.

## Step 3: Run the experiment

```bash
KEEP=1 make 07-node-pressure-eviction
```

`KEEP=1` leaves the pods in place afterwards so you can inspect them. While it runs, the module:

1. Works out how much memory the worker has available.
2. Edits `/var/lib/kubelet/config.yaml` on the node so `evictionHard: memory.available` is only about 600 MiB below that, then restarts the kubelet with `systemctl restart kubelet`.
3. Starts three pods:
   - `memory-hog`: BestEffort (no requests), grows to 1000 MiB.
   - `calm-burstable`: requests 32Mi, uses almost nothing.
   - `calm-guaranteed`: 32Mi request and limit, uses almost nothing.
4. Waits for the kubelet to react, then restores the original config.

## Step 4: See who got evicted

```bash
kubectl -n lab get pods -l module=07
```

```output
NAME              READY   STATUS    RESTARTS   AGE
calm-burstable    1/1     Running   0          17s
calm-guaranteed   1/1     Running   0          17s
memory-hog        0/1     Error     0          17s
```

```bash
kubectl -n lab get pod memory-hog -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
```

```output
Evicted: The node was low on resource: memory. Threshold quantity: 7141Mi, available: 7191604Ki.
Container main was using 721996Ki, request is 0, has larger consumption of memory.
```

**What it means:** the kubelet ranks pods by how far they are *above their memory request*. The hog had a request of 0 and was using about 700 MiB, so it was first in line. The calm pods were using less than they asked for, so they were safe.

## Eviction vs OOM kill

| | OOM kill (module 04) | Eviction (this module) |
|---|---|---|
| Who does it | The kernel | The kubelet |
| Trigger | One container hits its own `memory.max` | The whole node gets low on memory |
| What you see | `OOMKilled`, exit code 137, container restarts | `Evicted`, pod becomes `Failed` and is not restarted on this node |
| Who is chosen | The process that went over its limit | The pod furthest above its memory request |

A container using more than its request but less than its limit is fine as far as the kernel is concerned. It only becomes a target when the node runs short.

## Clean up

```bash
kubectl -n lab delete pod -l module=07
```

## Summary

- The kubelet watches `memory.available` and evicts pods when it falls below `evictionHard`.
- Pods using less than their memory request are evicted last. BestEffort pods, with a request of 0, go first.
- Evicted pods are not restarted on the same node. A Deployment creates a replacement, possibly on another node.

## Shortcut

`make 07-node-pressure-eviction` (without `KEEP=1`) runs the experiment, checks the hog was evicted and the calm pods weren't, and cleans up. If the hog isn't evicted on your machine, try `MARGIN_MI=400 make 07-node-pressure-eviction`.
