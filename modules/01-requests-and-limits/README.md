# 01 · Requests and limits become cgroup files

**What you'll learn:** the `resources:` block in a pod is just a way of writing numbers into files. You'll create one pod, then open those files yourself and match every line of YAML to a number.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Look at the pod

Open [`pod.yaml`](pod.yaml). The only part that matters is this:

```yaml
resources:
  requests: {cpu: 250m, memory: 64Mi}
  limits:   {cpu: 500m, memory: 128Mi}
```

Keep these four numbers in mind. By the end you'll have found where each one went.

## Step 2: Create it

```bash
kubectl create namespace lab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lab apply -f modules/01-requests-and-limits/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/requests-limits
```

The pod just runs `sleep`. It doesn't need to do anything; we only want to look at the box it lives in.

## Step 3: Find the CPU limit

With cgroups v2, every container sees its own cgroup folder at `/sys/fs/cgroup`. So "reading the container's limits" is just `cat`:

```bash
kubectl -n lab exec requests-limits -- cat /sys/fs/cgroup/cpu.max
```

You should see:

```text
50000 100000
```

**What it means:** "this container may use 50,000 microseconds of CPU in every 100,000 microseconds". That's 50ms per 100ms, or half a CPU. That's your `limits.cpu: 500m`.

## Step 4: Find the memory limit

```bash
kubectl -n lab exec requests-limits -- cat /sys/fs/cgroup/memory.max
```

```output
134217728
```

**What it means:** 134,217,728 bytes is exactly 128 MiB (128 × 1024 × 1024). That's your `limits.memory: 128Mi`. If the container ever needs more than this, the kernel kills it (module 04).

## Step 5: Find the CPU request

```bash
kubectl -n lab exec requests-limits -- cat /sys/fs/cgroup/cpu.weight
```

```output
35
```

(Your number may differ slightly with a different container runtime.)

**What it means:** a CPU request isn't a limit and isn't a reservation. It becomes a *weight*: when several containers fight for CPU, they get time in proportion to their weights. When the CPU is idle, the weight does nothing. Module 03 shows this in action.

## Step 6: Look for the memory request

```bash
kubectl -n lab exec requests-limits -- cat /sys/fs/cgroup/memory.min
```

```output
0
```

**What it means:** this is the surprise. `requests.memory: 64Mi` isn't written to any file the kernel uses. Only the scheduler uses it, to pick a node with enough room. At runtime it protects nothing.

## Step 7 (optional): Look from the node's side

A container only sees its own folder. The node sees the whole tree, including the folder for the *pod*. This helper finds it:

```bash
POD_DIR=$(./scripts/pod-cgroup.sh requests-limits)
echo "$POD_DIR"
docker exec under-the-hood-worker cat "$POD_DIR/cpu.max" "$POD_DIR/memory.max"
```

The pod folder holds the same limits, because a pod's limit is the sum of its containers' limits, and this pod has one container.

## Clean up

```bash
kubectl -n lab delete pod requests-limits
```

## Summary

| You wrote | File | Value | In plain words |
|---|---|---|---|
| `limits.cpu: 500m` | `cpu.max` | `50000 100000` | At most 50ms of CPU every 100ms |
| `limits.memory: 128Mi` | `memory.max` | `134217728` | 128 MiB, then the kernel kills it |
| `requests.cpu: 250m` | `cpu.weight` | `35` | A share of CPU, only used when CPUs are busy |
| `requests.memory: 64Mi` | `memory.min` | `0` | Nothing. Only the scheduler uses it |

## Shortcut

`make 01-requests-and-limits` runs every step above in one go and checks the values for you. Use it to confirm everything works, or to rerun quickly. Follow the steps by hand the first time; that's where the learning is.
