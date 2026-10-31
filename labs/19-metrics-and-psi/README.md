# 19 · Seeing it in production: metrics and pressure

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 10 minutes · **Blog:** [chapter 19](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#19-seeing-it-in-production)
>
> **You'll learn:** which Prometheus metric comes from which cgroup file, and how pressure (PSI) shows waiting that usage graphs can't.

## The question

I can't `cat` files on production nodes all day. What do I watch instead?

## Predict first

<details>
<summary>A pod runs twice as many busy threads as the node has CPUs, with no limit. Its CPU usage is high. What will <code>cpu.pressure</code> say?</summary>

That some of its threads were waiting for a CPU most of the time: <code>some avg10</code> well above 50%. Usage says how busy you are; pressure says how long things waited.
</details>

## Steps

```bash
kubectl apply -f labs/19-metrics-and-psi/pods.yaml
kubectl wait --for=condition=Ready pod/psi-cpu pod/psi-memory --timeout=120s
sleep 30
kubectl exec psi-cpu -- cat /sys/fs/cgroup/cpu.pressure
kubectl exec psi-memory -- cat /sys/fs/cgroup/memory.pressure
```

```text
some avg10=75.19 avg60=24.03 avg300=5.60 total=17362896
full avg10=0.15 avg60=0.07 avg300=0.01 total=209848
```

(That's `psi-cpu` on my machine.)

| Part | Meaning |
|---|---|
| `some` | Share of time at least one task was waiting |
| `full` | Share of time every task was waiting at once |
| `avg10`, `avg60`, `avg300` | Averages over 10 s, 1 min and 5 min, in percent |

The node has the same files in `/proc/pressure/`:

```bash
docker exec under-the-hood-worker cat /proc/pressure/cpu /proc/pressure/memory
```

## What happened

Every file in these labs already has a metric. cAdvisor, built into the kubelet, reads the cgroup files and exports them:

| Kernel file | Prometheus metric |
|---|---|
| `cpu.stat` → `usage_usec` | `container_cpu_usage_seconds_total` |
| `cpu.stat` → `nr_periods` / `nr_throttled` | `container_cpu_cfs_periods_total` / `container_cpu_cfs_throttled_periods_total` |
| `cpu.stat` → `throttled_usec` | `container_cpu_cfs_throttled_seconds_total` |
| `memory.current` − `inactive_file` | `container_memory_working_set_bytes` |
| `memory.stat` → `anon` / `file` | `container_memory_rss` / `container_memory_cache` |
| `memory.events` → `oom_kill` | `container_oom_events_total` |

Since Kubernetes 1.36 the kubelet also exports pressure as stable metrics, for nodes, pods and containers. When a pod is slow but its CPU and memory graphs look fine, check pressure. Rising `memory.pressure` is often the earliest warning before an OOM kill.

> **In one line:** every cgroup file has a metric. Watch the throttle ratio, the working set and OOM events, and use pressure when graphs look fine but users don't.

Check your work: `make check LAB=19`

## Clean up

```bash
kubectl delete -f labs/19-metrics-and-psi/ --ignore-not-found
```

**Next:** [lab 20 · PIDs and disk](../20-pids-and-disk/) (needs `make cluster PROFILE=pids`)
