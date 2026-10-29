# 10 · LimitRange

**What you'll learn:** how to give every container in a namespace sensible default requests and limits, and how to block values that are too big.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Create a namespace with rules

```bash
kubectl apply -f modules/10-limitrange/limitrange.yaml
kubectl -n lab-limits describe limitrange container-defaults
```

```output
Type        Resource  Min   Max    Default Request  Default Limit
Container   memory    32Mi  256Mi  64Mi             128Mi
Container   cpu       -     -      100m             200m
```

**What a LimitRange is:** a set of rules for each container in a namespace:

- **Default Request / Default Limit:** filled in when a container doesn't set its own.
- **Min / Max:** anything outside this range is refused.

## Step 2: Create a pod with no resources at all

Open [`pod-no-resources.yaml`](pod-no-resources.yaml): there's no `resources:` section.

```bash
kubectl apply -f modules/10-limitrange/pod-no-resources.yaml
kubectl -n lab-limits wait --for=condition=Ready pod/lr-defaults
kubectl -n lab-limits get pod lr-defaults -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```

```output
{"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
```

**What happened:** Kubernetes filled in the defaults *before saving the pod*. It also leaves a note saying so:

```bash
kubectl -n lab-limits get pod lr-defaults -o jsonpath='{.metadata.annotations.kubernetes\.io/limit-ranger}{"\n"}'
```

```output
LimitRanger plugin set: cpu, memory request for container main; cpu, memory limit for container main
```

## Step 3: Prove the defaults are real

```bash
kubectl -n lab-limits exec lr-defaults -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
```

```output
20000 100000
134217728
```

**What it means:** the injected `200m` CPU limit became `cpu.max` (20 ms per 100 ms) and the `128Mi` memory limit became `memory.max` (134,217,728 bytes), exactly like hand-written values in module 01. The kubelet and the kernel can't tell the difference.

## Step 4: Try something too big

```bash
kubectl apply -f modules/10-limitrange/pod-too-big.yaml      # memory limit 512Mi
```

```output
Error from server (Forbidden): ... maximum memory usage per Container is 256Mi, but limit is 512Mi
```

## Things worth knowing

- Rules only apply to pods created *after* the LimitRange exists.
- If a container sets only a limit, Kubernetes copies it into the request before the LimitRange looks, so the request equals the limit.
- LimitRange and ResourceQuota (module 09) work well together: the quota demands requests, and the LimitRange quietly provides them.

## Clean up

```bash
kubectl delete namespace lab-limits
```

## Shortcut

`make 10-limitrange` runs all of this and checks the defaults, the cgroup files and the rejection.
