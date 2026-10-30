# 11 · Pressure stall information (PSI)

**What you'll learn:** how to measure how much time a pod spends *waiting* for CPU, memory or disk, which normal usage graphs can't show you.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## The idea

Usage tells you how busy something is. Pressure tells you how long things waited.

Think of a shop with one till. "The till was busy 100% of the time" (usage) sounds the same whether one customer was served all day or fifty people queued out of the door. Pressure measures the queue.

## Step 1: Check your kernel supports it

```bash
docker exec under-the-hood-worker cat /proc/pressure/cpu
```

```output
some avg10=0.00 avg60=0.00 avg300=0.21 total=129693248
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
```

If this file doesn't exist, PSI is switched off in your kernel and the module will print `SKIP`.

**How to read it:**

| Part | Meaning |
|---|---|
| `some` | Share of time at least one task was stuck waiting |
| `full` | Share of time *every* task was stuck at once: no progress at all |
| `avg10`, `avg60`, `avg300` | Averages over the last 10 seconds, 1 minute and 5 minutes, as percentages |
| `total` | Total time spent waiting since boot, in microseconds |

`/proc/pressure/` covers the whole node. Every cgroup also has its own copy: `cpu.pressure`, `memory.pressure` and `io.pressure`.

## Step 2: Create a CPU queue

`psi-cpu` runs twice as many busy loops as the node has CPUs, with no limit, so its threads always outnumber the CPUs. `psi-memory` keeps rereading a 192 MiB file inside a 64Mi memory limit, so the kernel has to keep throwing away cached file data to make room.

```bash
kubectl create namespace lab            # skip if it already exists
THREADS=$(( $(docker exec under-the-hood-worker nproc) * 2 ))
sed "s/__THREADS__/$THREADS/g" modules/11-psi/pods.yaml | kubectl -n lab apply -f -
kubectl -n lab wait --for=condition=Ready pod/psi-cpu pod/psi-memory
sleep 20
```

## Step 3: Read the pressure

```bash
kubectl -n lab exec psi-cpu -- cat /sys/fs/cgroup/cpu.pressure
```

From a real run (20 threads on 10 CPUs):

```text
some avg10=75.19 avg60=24.03 avg300=5.60 total=17362896
full avg10=0.15 avg60=0.07 avg300=0.01 total=209848
```

**What it means:** over the last 10 seconds, at least one of this pod's threads was waiting for a CPU 75% of the time. `avg60` is lower only because the pod hasn't been running for a full minute yet.

```bash
kubectl -n lab exec psi-memory -- cat /sys/fs/cgroup/memory.pressure /sys/fs/cgroup/io.pressure
```

Here, any non-zero `some` means the pod spent time waiting for the kernel to free memory, or for the disk while it reread data it had just thrown away. How much depends on your disk's speed.

## Why it matters in production

When a service is slow but its CPU and memory graphs look fine, check pressure. High `cpu.pressure` means it's waiting for CPU (too many threads, or a noisy neighbour). Rising `memory.pressure` is often the earliest warning before an OOM kill. Kubernetes can expose these numbers through the kubelet, so you can graph and alert on them.

## Clean up

```bash
kubectl -n lab delete pod psi-cpu psi-memory
```

## Summary

| File | Measures |
|---|---|
| `cpu.pressure` | Time spent waiting for a CPU |
| `memory.pressure` | Time spent waiting for memory to be freed |
| `io.pressure` | Time spent waiting for the disk |
| `/proc/pressure/*` | The same, for the whole node |

## Shortcut

`make 11-psi` runs all of this and checks that CPU pressure on `psi-cpu` went above 10%.
