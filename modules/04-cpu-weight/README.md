# 04 · CPU weight under contention

**What you'll learn:** what a CPU *request* does at runtime. Spoiler: it isn't a reservation, it's a share, and it only matters when CPUs are busy.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Look at the two pods

Open [`pods.yaml`](pods.yaml). Both pods run one busy loop per CPU on the node, so together they want twice the node's CPU. Neither has a CPU limit. The only difference is the request:

| Pod | CPU request |
|---|---|
| `weight-low` | `100m` |
| `weight-high` | `800m` |

## Step 2: Start them

The manifest has a placeholder, `__THREADS__`, for the number of busy loops. Fill it in with the node's CPU count:

```bash
kubectl create namespace lab            # skip if it already exists
THREADS=$(docker exec under-the-hood-worker nproc)
echo "the node has $THREADS CPUs"
sed "s/__THREADS__/$THREADS/g" modules/04-cpu-weight/pods.yaml | kubectl -n lab apply -f -
kubectl -n lab wait --for=condition=Ready pod/weight-low pod/weight-high
```

## Step 3: Read the weights

```bash
kubectl -n lab exec weight-low  -- cat /sys/fs/cgroup/cpu.weight
kubectl -n lab exec weight-high -- cat /sys/fs/cgroup/cpu.weight
```

```output
17
84
```

**What `cpu.weight` is:** a number from 1 to 10,000 (default 100). When several groups want more CPU than exists, the kernel's scheduler gives each one time *in proportion to its weight*. When CPUs are idle, nobody waits and the weight does nothing.

Kubernetes writes your request here, but not as a straight copy. It takes two conversions:

1. The kubelet turns millicores into **CPU shares**, the unit from cgroups v1: `shares = millicores × 1024 / 1000`. So 100m is 102 shares and 800m is 819.
2. The container runtime (runc or crun) turns shares into a cgroup v2 **weight**.

Step 2 changed recently. Older runtimes used a straight line, `weight = 1 + (shares − 2) × 9999 / 262142`. That made a pod requesting a whole CPU weigh only 39 against the default of 100 that ordinary system services get, so Kubernetes pods lost out under contention. Newer runtimes (runc 1.3.2+, crun 1.23+) use a curve instead, chosen so that one CPU lands at about 100:

| Request | Shares | Old formula | New formula | This lab |
|---|---|---|---|---|
| 100m | 102 | 4 | 17 | 17 |
| 800m | 819 | 32 | 84 | 84 |

If your numbers match the "new" column, your runtime uses the new formula. Either way, what matters is the *ratio* between pods competing for the same CPUs.

## Step 4: Measure who gets what

`cpu.stat` has a line `usage_usec`: total CPU time used, in microseconds. Read it for both pods, wait 10 seconds, read again:

```bash
for p in weight-low weight-high; do kubectl -n lab exec $p -- grep usage_usec /sys/fs/cgroup/cpu.stat; done
sleep 10
for p in weight-low weight-high; do kubectl -n lab exec $p -- grep usage_usec /sys/fs/cgroup/cpu.stat; done
```

For each pod, subtract the first number from the second and divide by 10,000. That's the CPU it used, in millicores (1000 = one full CPU).

A real run on a 10-CPU node, measured by the shortcut:

```text
  CPU split high/low    8.2x
  request ratio         8.0x  (800m / 100m)
```

**What it means:** with both pods fighting over every CPU, `weight-high` got about 8 times more CPU time than `weight-low`, close to the ratio of their requests. That's one run, not a guarantee: the real split depends on the whole cgroup tree and whatever else is competing for the CPUs.

## Why it matters in production

A request is your guaranteed *share* when the node is busy. Set it too low and a noisy neighbour can squeeze you; set it too high and you waste capacity, because the scheduler reserves room for it on the node.

## Clean up

```bash
kubectl -n lab delete pod weight-low weight-high
```

## Summary

| You wrote | File | What it does |
|---|---|---|
| `requests.cpu` | `cpu.weight` | Your share of CPU time when the node is busy. Does nothing when it's idle |
| (no `limits.cpu`) | `cpu.max` = `max` | No cap, so either pod can use idle CPUs freely |

## Shortcut

`make 04-cpu-weight` runs all of this and checks that the bigger request got at least 3x more CPU.
