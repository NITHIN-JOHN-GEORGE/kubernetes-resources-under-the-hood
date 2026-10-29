# 06 · Node allocatable and reservations

**What you'll learn:** how much of a node Kubernetes is willing to hand out to pods, and what happens when a pod asks for more.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Capacity vs allocatable

```bash
kubectl get node under-the-hood-worker -o jsonpath='{.status.capacity.memory}{"  capacity\n"}{.status.allocatable.memory}{"  allocatable\n"}'
```

From a real run (your numbers depend on Docker's settings):

```text
8126480Ki  capacity
8126480Ki  allocatable
```

**What these mean:**

- **Capacity** is everything the node has.
- **Allocatable** is the part the scheduler may hand out to pods. It's capacity minus whatever is reserved for the operating system, for Kubernetes' own programs, and as a safety margin.

`Ki` means kibibytes (1024 bytes), so 8,126,480 Ki is about 7.75 GiB.

## Step 2: See what's reserved

```bash
kubectl get --raw /api/v1/nodes/under-the-hood-worker/proxy/configz | grep -oE '"(systemReserved|kubeReserved|evictionHard)":\{[^}]*\}'
```

```output
"evictionHard":{"imagefs.available":"0%","nodefs.available":"0%","nodefs.inodesFree":"0%"}
```

**What it means:**

| Setting | Holds back memory for |
|---|---|
| `systemReserved` | The operating system: systemd, logging, SSH |
| `kubeReserved` | Kubernetes itself: the kubelet and the container runtime |
| `evictionHard` | A safety margin. When free memory drops below it, the kubelet starts evicting pods (module 07) |

kind sets none of the first two and only disk thresholds for the third, which is why capacity and allocatable are equal here. On GKE or EKS you'd see several hundred MiB or more held back.

## Step 3: Read the ceiling for all pods

```bash
docker exec under-the-hood-worker cat /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/memory.max
```

```output
8321515520
```

**What it means:** this is the `memory.max` of the box that holds every pod (module 00). 8,321,515,520 bytes is exactly 8,126,480 Ki, the node's capacity. The kubelet sets this to capacity minus `systemReserved` minus `kubeReserved`. It doesn't subtract the eviction margin; the kubelet enforces that one by evicting pods instead.

## Step 4: Ask for too much

The manifest has a placeholder, `__MEM__`. Fill it with 1 GiB more than the node's allocatable memory:

```bash
kubectl create namespace lab            # skip if it already exists
ALLOC_KI=$(kubectl get node under-the-hood-worker -o jsonpath='{.status.allocatable.memory}' | tr -d 'Ki')
MEM="$(( ALLOC_KI / 1024 + 1024 ))Mi"
echo "asking for $MEM"
sed "s/__MEM__/$MEM/" modules/06-node-allocatable/pod.yaml | kubectl -n lab apply -f -
kubectl -n lab get pod too-big
```

```output
NAME      READY   STATUS    RESTARTS   AGE
too-big   0/1     Pending   0          2s
```

## Step 5: Ask why

```bash
kubectl -n lab get pod too-big -o jsonpath='{.status.conditions[0].message}{"\n"}'
```

```output
0/2 nodes are available: 1 Insufficient memory, 1 node(s) had untolerated taint(s). ...
```

**What it means:** the scheduler checked both nodes. The worker doesn't have enough allocatable memory for the *request*. The control-plane node has a taint that keeps ordinary pods off it. So the pod waits, forever, until something changes.

The scheduler only compares **requests** with allocatable. It never looks at how much memory is actually in use. A node can be "full" while nearly idle, or overloaded while "empty", depending on how honest the requests are.

## Clean up

```bash
kubectl -n lab delete pod too-big
```

## Summary

| Term | Meaning |
|---|---|
| Capacity | Everything the node has |
| Allocatable | Capacity minus reservations: what the scheduler can hand out |
| Pod tree `memory.max` | Hard ceiling for all pods together, enforced by the kernel |
| `Insufficient memory` | No node has enough allocatable left for the pod's *request* |

## Shortcut

`make 06-node-allocatable` runs all of this and checks the pod stays `Pending` for the right reason.
