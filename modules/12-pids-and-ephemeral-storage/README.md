# 12 · PIDs and ephemeral storage

**What you'll learn:** two limits people forget about: how many processes a pod may start, and how much of the node's disk it may fill.

**Time:** about 10 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Part 1: Process limits

### Why it matters

Every process and thread on Linux gets a number, its PID (process ID), and a machine only has so many. A buggy program that keeps starting processes, often called a *fork bomb*, can use them all up. Then nothing else on the node can start a process, not even the kubelet.

The fix is the cgroup `pids` controller: a per-group cap on the number of processes.

### Step 1: Run the experiment

The limit is a kubelet setting called `podPidsLimit`, which applies to every pod on the node. Changing it means editing the kubelet's config and restarting it, so let the module do that part:

```bash
KEEP=1 make 12-pids-and-ephemeral-storage
```

It sets `podPidsLimit: 64`, restarts the kubelet, starts a pod called `pid-hog` that tries to launch 100 background processes, records the results, and puts the original kubelet config back. `KEEP=1` leaves the pods for you to inspect.

### Step 2: See it fail to start them all

```bash
kubectl -n lab logs pid-hog | tail -3
```

You'll see the count stop short of 100, with an error like `can't fork: Resource temporarily unavailable`.

**What it means:** *fork* is how a Linux process starts a new one. When the group is at its limit, the kernel refuses with "resource temporarily unavailable" (the error code `EAGAIN`).

### Step 3: Read the kernel's side

```bash
POD_DIR=$(./scripts/pod-cgroup.sh pid-hog)
docker exec under-the-hood-worker cat "$POD_DIR/pids.max" "$POD_DIR/pids.current"
docker exec under-the-hood-worker sh -c "cat $POD_DIR/pids.events $POD_DIR/*/pids.events"
```

| File | Meaning |
|---|---|
| `pids.max` | The cap: `64`, from `podPidsLimit` |
| `pids.current` | How many processes and threads are in the group now. It never goes past `pids.max` |
| `pids.events` | `max N`: how many times a new process was refused because of the cap |

Depending on your kernel version, the `max` count shows up on the pod's folder, the container's folder, or both, which is why the last command reads both.

## Part 2: Disk space

### Why it matters

Containers write to the node's disk all the time: logs, temporary files, and `emptyDir` volumes. One pod writing a runaway log file can fill the disk. Then the node reports `DiskPressure`, and the kubelet starts evicting pods, including ones that did nothing wrong.

### Step 4: Watch a pod go over its disk limit

The shortcut above already started `disk-hog`. Open [`pod-disk.yaml`](pod-disk.yaml): it has `limits.ephemeral-storage: 50Mi` and writes 100 MiB into an `emptyDir` volume.

```bash
kubectl -n lab get pod disk-hog -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
```

```output
Evicted: Pod ephemeral local storage usage exceeds the total limit of containers 50Mi.
```

**What it means:** there's no cgroup file for disk space. Instead, the kubelet regularly adds up how much each pod has written (its writable layer, its logs and its `emptyDir` volumes) and evicts the pod when the total goes over the limit. Because it's a periodic check, the write itself succeeds and the eviction comes a little later.

To try it yourself from scratch:

```bash
kubectl -n lab delete pod disk-hog
kubectl -n lab apply -f modules/12-pids-and-ephemeral-storage/pod-disk.yaml
kubectl -n lab get pod disk-hog -w          # can take up to a minute
```

## Clean up

```bash
kubectl -n lab delete pod -l module=12
```

## Summary

| Limit | Set by | Enforced by | What happens |
|---|---|---|---|
| Processes | `podPidsLimit` in the kubelet config | The kernel (`pids.max`) | New processes are refused |
| Disk | `limits.ephemeral-storage` on the container | The kubelet, by measuring | The pod is evicted |

## Shortcut

`make 12-pids-and-ephemeral-storage` (without `KEEP=1`) runs both parts, checks the results and cleans up.
