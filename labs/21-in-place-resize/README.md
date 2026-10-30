# 21 · Finale: resize a running pod

> **Runs on:** the kind cluster (`make cluster`), Kubernetes 1.33 or newer · **Time:** 5 minutes · **Blog:** [chapter 21](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#21-finale-resize-a-running-pod)
>
> **You'll learn:** that changing a pod's CPU and memory in place is just the kubelet rewriting cgroup files, like you did by hand in lab 08.

## The question

If limits are just numbers in files, can we change them on a live pod?

## Predict first

<details>
<summary>You raise a running pod's CPU from 200m to 500m. Does the container restart?</summary>

No. The kubelet asks the runtime to rewrite <code>cpu.max</code> (and <code>memory.max</code>) of the live container. Same container, same process, new numbers.
</details>

## Steps

```bash
kubectl apply -f labs/21-in-place-resize/pod.yaml
kubectl wait --for=condition=Ready pod/resize-demo --timeout=120s
kubectl exec resize-demo -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
```

Now resize it while it runs:

```bash
kubectl patch pod resize-demo --subresource resize --patch \
  '{"spec":{"containers":[{"name":"main","resources":{"requests":{"cpu":"500m","memory":"128Mi"},"limits":{"cpu":"500m","memory":"128Mi"}}}]}}'
sleep 5
kubectl exec resize-demo -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
kubectl get pod resize-demo -o jsonpath='restarts={.status.containerStatuses[0].restartCount}{"\n"}'
```

```text
20000 100000
67108864
50000 100000
134217728
restarts=0
```

## What happened

The kubelet asked the runtime to rewrite the files of the live container: `cpu.max` from 20000 to 50000, `memory.max` from 64 MiB to 128 MiB, with no restart. In-place resize is on by default since Kubernetes 1.33.

> **In one line:** resize rewrites the cgroup files of a live container. No restart, because there's nothing to restart: it's just a file.

Check your work: `make check LAB=21`

## Clean up

```bash
kubectl delete -f labs/21-in-place-resize/ --ignore-not-found
```

**Next:** the extras ([E1 · ResourceQuota](../E1-resourcequota/)), or try the [incidents](../../incidents/).
