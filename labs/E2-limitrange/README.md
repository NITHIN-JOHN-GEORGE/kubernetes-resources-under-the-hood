# E2 · LimitRange

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 5 minutes · **Blog:** [cheat sheet](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#cheat-sheet)
>
> **You'll learn:** how a namespace can fill in default requests and limits, and that the injected defaults land in `cpu.max` and `memory.max` like hand-written ones.

## The question

What happens to a pod that sets no resources at all, in a namespace with rules?

## Predict first

<details>
<summary>The namespace's default limit is 200m CPU and 128Mi memory. A pod sets nothing. What will its <code>cpu.max</code> say?</summary>

<code>20000 100000</code>. The API server fills in the defaults before the pod is saved, so the kubelet and the kernel can't tell them from values you wrote.
</details>

## Steps

```bash
kubectl apply -f labs/E2-limitrange/limitrange.yaml
kubectl -n lab-limits describe limitrange container-defaults
```

A pod with no `resources:` section:

```bash
kubectl apply -f labs/E2-limitrange/pod-no-resources.yaml
kubectl -n lab-limits wait --for=condition=Ready pod/lr-defaults --timeout=120s
kubectl -n lab-limits get pod lr-defaults -o jsonpath='{.spec.containers[0].resources}{"\n"}'
kubectl -n lab-limits exec lr-defaults -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
```

```text
{"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
20000 100000
134217728
```

And one that asks for more than the namespace allows:

```bash
kubectl apply -f labs/E2-limitrange/pod-too-big.yaml
```

```text
Error from server (Forbidden): ... maximum memory usage per Container is 256Mi, but limit is 512Mi
```

## What happened

A LimitRange is a set of per-container rules: defaults for requests and limits, plus a minimum and maximum. The defaults are written into the pod spec at admission, and from there they become cgroup files like any others. Rules only apply to pods created after the LimitRange exists.

> **In one line:** a LimitRange fills in missing requests and limits, and its defaults end up in the same cgroup files.

Check your work: `make check LAB=E2`

## Clean up

```bash
kubectl delete -f labs/E2-limitrange/ --ignore-not-found
```

**Next:** [E3 · Priority and preemption](../E3-priority-and-preemption/)
