# 20 · The other limits: PIDs and disk

> **Runs on:** the kind cluster with the pids profile: `make clean && make cluster PROFILE=pids` · **Time:** 10 minutes · **Blog:** [chapter 20](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#20-the-other-limits-briefly)
>
> **You'll learn:** that the number of processes is capped by a cgroup, and that disk space isn't: the kubelet measures it and evicts.

## The question

Is it only CPU and memory?

## Predict first

<details>
<summary>A pod tries to start 100 processes, but <code>pids.max</code> is 64. What happens to the pod?</summary>

It keeps running. The kernel refuses the forks past the limit (<code>can't fork</code>), and only the code that tried to fork fails. Nothing is killed.
</details>

## Steps

This profile sets the kubelet's `podPidsLimit` to 64. **PIDs:**

```bash
kubectl apply -f labs/20-pids-and-disk/pod-pids.yaml
kubectl wait --for=condition=Ready pod/pid-hog --timeout=120s
sleep 3
docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh pid-hog)/pids.max"
docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh pid-hog)/pids.current"
kubectl logs pid-hog | tail -3
```

`pids.max` is `64` on the **pod** cgroup, `pids.current` sits at the limit, and the log shows the forks the kernel refused. The pod is still `Running`.

**Disk.** A pod with a 50Mi `ephemeral-storage` limit writes 100 MiB into an `emptyDir`:

```bash
kubectl apply -f labs/20-pids-and-disk/pod-disk.yaml
for i in $(seq 24); do
  [ "$(kubectl get pod disk-hog -o jsonpath='{.status.reason}')" = Evicted ] && break
  sleep 5
done
kubectl get pod disk-hog -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
```

`Evicted`, with a message about the ephemeral-storage limit. There's no cgroup file for this: the kubelet adds up what the pod has written (its logs, its writable layer and `emptyDir` volumes) and evicts it.

## What happened

| Limit | Cgroup file | Set by | What happens |
|---|---|---|---|
| Number of processes | `pids.max` | the kubelet's `podPidsLimit` | New processes are refused |
| Disk space | **none** | `limits.ephemeral-storage` | The kubelet measures and evicts |

Every process and thread needs a PID, and a node only has so many. One runaway pod (a *fork bomb*) could use them all, and then nothing on the node could start, not even the kubelet.

> **In one line:** PIDs are capped by a cgroup. Disk space isn't: the kubelet measures it and evicts.

Check your work: `make check LAB=20`

## Clean up

```bash
kubectl delete -f labs/20-pids-and-disk/ --ignore-not-found
```

Go back to the default cluster when you're done: `make clean && make cluster`.

**Next:** [lab 21 · Resize a running pod](../21-in-place-resize/)
