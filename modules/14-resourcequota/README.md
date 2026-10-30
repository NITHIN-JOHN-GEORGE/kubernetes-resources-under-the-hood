# 14 · ResourceQuota

**What you'll learn:** how to cap the total resources a whole namespace (say, one team) can ask for, and how Kubernetes refuses pods that would go over.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Create a namespace with a budget

```bash
kubectl apply -f modules/14-resourcequota/quota.yaml
kubectl -n lab-quota describe quota compute
```

```output
Resource         Used  Hard
--------         ----  ----
limits.memory    0     512Mi
pods             0     3
requests.cpu     0     500m
requests.memory  0     256Mi
```

**What a ResourceQuota is:** a budget for a namespace. `Hard` is the budget; `Used` is the total of what the pods in the namespace have asked for so far.

## Step 2: Try a pod with no requests

```bash
kubectl apply -f modules/14-resourcequota/pod-no-requests.yaml
```

```output
Error from server (Forbidden): ... failed quota: compute: must specify limits.memory for: main; requests.cpu for: main; requests.memory for: main
```

**What it means:** once a quota counts something, every pod must declare it. Otherwise Kubernetes couldn't tell how much of the budget it uses.

## Step 3: Try a pod that fits

```bash
kubectl apply -f modules/14-resourcequota/pod-small.yaml     # asks for 200m CPU
```

```output
pod/q-small created
```

## Step 4: Try a pod that would go over

```bash
kubectl apply -f modules/14-resourcequota/pod-big.yaml       # asks for 400m CPU
```

```output
Error from server (Forbidden): ... exceeded quota: compute, requested: requests.cpu=400m, used: requests.cpu=200m, limited: requests.cpu=500m
```

**What it means:** 200m is used, and 400m more would make 600m, over the 500m budget.

```bash
kubectl -n lab-quota describe quota compute
```

```output
Resource         Used   Hard
limits.memory    128Mi  512Mi
pods             1      3
requests.cpu     200m   500m
requests.memory  100Mi  256Mi
```

## Things worth knowing

- **It's checked when the pod is created, not while it runs.** A rejected pod never exists. With a Deployment, you won't see an error on any pod; look at the ReplicaSet's events for `FailedCreate`.
- **It counts what pods ask for, not what they use.** A pod using ten times its request still counts as its request.
- **No cgroup file is involved.** Nothing changes on the node.
- Quotas can also cap object counts (services, volumes, deployments) and can apply to just one priority class.

## Clean up

```bash
kubectl delete namespace lab-quota
```

## Shortcut

`make 14-resourcequota` runs all three pods and checks each result.
