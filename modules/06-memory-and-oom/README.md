# 06 · Memory limits and OOM kills

**What you'll learn:** what happens when a container uses more memory than its limit, and where the kernel leaves the evidence.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Look at the pod

Open [`pod.yaml`](pod.yaml). `memory-hog` has a 64Mi memory limit. Inside it, a small Python script grabs 10 MiB of memory every 0.3 seconds, prints how much it has, and never lets go.

## Step 2: Start it and watch

```bash
kubectl create namespace lab            # skip if it already exists
kubectl -n lab apply -f modules/06-memory-and-oom/pod.yaml
kubectl -n lab get pod memory-hog -w
```

Within a few seconds you'll see something like this:

```text
NAME         READY   STATUS      RESTARTS
memory-hog   1/1     Running     0
memory-hog   0/1     OOMKilled   0
memory-hog   1/1     Running     1
```

Press Ctrl-C to stop watching. Kubernetes restarts the container, it fills up again, and it gets killed again, over and over.

## Step 3: See how far it got

`--previous` shows the logs of the container that just died:

```bash
kubectl -n lab logs memory-hog --previous | tail -3
```

```output
allocated 40 MiB
allocated 50 MiB
allocated 60 MiB
```

**What it means:** it never printed 70. The limit is 64 MiB, but the Python interpreter itself also lives in that box and uses memory, so the script's own data never reaches 64.

## Step 4: See how Kubernetes recorded it

```bash
kubectl -n lab get pod memory-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated}{"\n"}'
```

Look for `"reason":"OOMKilled"` and `"exitCode":137`.

**What exit code 137 means:** when a process is killed by a signal, its exit code is 128 plus the signal number. Signal 9 is `SIGKILL`, the one that can't be caught or ignored. 128 + 9 = 137. The process got no chance to clean up or log anything.

## Step 5: Find the kernel's own records

The memory limit is enforced by the kernel's **OOM killer** (out of memory). It keeps a tally for every cgroup in a file called `memory.events`. Find the pod's folder on the node and read it:

```bash
POD_DIR=$(./scripts/pod-cgroup.sh memory-hog)
docker exec under-the-hood-worker cat "$POD_DIR/memory.events"
docker exec under-the-hood-worker cat "$POD_DIR/memory.max"
```

From a real run:

```text
low 0
high 0
max 75
oom 2
oom_kill 4
oom_group_kill 2

67108864
```

**What each line means:**

| Field | Meaning |
|---|---|
| `max` | How many times usage hit `memory.max` and the kernel had to try to free memory |
| `oom` | How many times freeing memory failed, so the kernel had to kill something |
| `oom_kill` | How many processes it killed |
| `oom_group_kill` | How many times it killed a whole group of processes together |
| `low`, `high` | Softer limits that Kubernetes doesn't set by default, so they stay 0 |

**What `memory.max` is:** the hard memory ceiling, in bytes. 67,108,864 is exactly 64 MiB (64 × 1024 × 1024).

`oom_group_kill` appears because the kubelet turns on `memory.oom.group` for each container. When one process in the container is killed, the kernel kills the rest of the container with it, so nothing is left half-alive.

## Why memory is killed and CPU isn't

When a container wants more CPU than allowed, the kernel can make it wait a few milliseconds (module 05). Memory can't work like that: if a program needs more memory and the box is full, waiting doesn't free any. Before giving up, the kernel tries to reclaim memory that can be dropped, such as cached file data. When there's nothing left to reclaim, the only option is to kill a process.

## Clean up

```bash
kubectl -n lab delete pod memory-hog
```

## Summary

| Where | What you saw |
|---|---|
| `kubectl get pod` | `OOMKilled`, and the restart count going up |
| `lastState.terminated` | `exitCode: 137`, killed by signal 9 |
| `memory.events` | The kernel's own count: limits hit (`max`) and processes killed (`oom_kill`) |
| `memory.max` | The limit in bytes |

## Shortcut

`make 06-memory-and-oom` runs all of this and checks for `OOMKilled`, an `oom_kill` count, and the right `memory.max`.
