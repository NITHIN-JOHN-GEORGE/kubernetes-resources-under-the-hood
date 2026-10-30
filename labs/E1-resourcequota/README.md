# E1 · ResourceQuota

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 5 minutes · **Blog:** [cheat sheet](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#cheat-sheet)
>
> **You'll learn:** how to cap what a whole namespace can ask for, and how the API server refuses pods that would go over. No cgroup is involved.

## The question

How do you stop one team from asking for the whole cluster?

## Predict first

<details>
<summary>A namespace's quota allows 500m of CPU requests. 200m is already used. What happens to a pod asking for 400m?</summary>

It's refused at the API server: <code>exceeded quota</code>. It never exists, so it never reaches a node.
</details>

## Steps

```bash
kubectl apply -f labs/E1-resourcequota/quota.yaml
sleep 2
kubectl -n lab-quota describe quota compute
```

A pod with no requests at all, a pod that fits, and a pod that would go over:

```bash
kubectl apply -f labs/E1-resourcequota/pod-no-requests.yaml
kubectl apply -f labs/E1-resourcequota/pod-small.yaml
kubectl apply -f labs/E1-resourcequota/pod-big.yaml
kubectl -n lab-quota describe quota compute
```

```text
Error from server (Forbidden): ... failed quota: compute: must specify limits.memory for: main; requests.cpu for: main; requests.memory for: main
pod/q-small created
Error from server (Forbidden): ... exceeded quota: compute, requested: requests.cpu=400m, used: requests.cpu=200m, limited: requests.cpu=500m
```

## What happened

- Once a quota counts something, every pod must declare it, or Kubernetes couldn't tell how much of the budget it uses.
- It counts what pods **ask for**, not what they use, and it's checked when the pod is created, not while it runs.
- With a Deployment you won't see the error on a pod: look at the ReplicaSet's events for `FailedCreate`.

> **In one line:** a ResourceQuota is a namespace's budget for requests and limits, enforced by the API server.

Check your work: `make check LAB=E1`

## Clean up

```bash
kubectl delete -f labs/E1-resourcequota/ --ignore-not-found
```

**Next:** [E2 · LimitRange](../E2-limitrange/)
