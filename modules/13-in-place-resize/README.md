# 13 · In-place pod resize

**What you'll learn:** how to change a running pod's CPU and memory without restarting it, and proof that it really is just rewriting the cgroup files.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`, Kubernetes 1.33 or newer, and kubectl 1.32 or newer. Run every command from the repo folder.

---

## Step 1: Start a pod

```bash
kubectl create namespace lab            # skip if it already exists
kubectl -n lab apply -f modules/13-in-place-resize/pod.yaml
kubectl -n lab wait --for=condition=Ready pod/resize-demo
```

`resize-demo` asks for 200m CPU and 64Mi memory, with limits equal to requests.

## Step 2: Note its files and identity

```bash
kubectl -n lab exec resize-demo -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
kubectl -n lab get pod resize-demo -o jsonpath='{.status.containerStatuses[0].containerID}{"\n"}'
```

```output
20000 100000
67108864
containerd://3f9c…
```

`20000 100000` is 200m (20 ms per 100 ms), `67108864` is 64 MiB. Keep the container ID; it's the container's unique identity. A restarted container gets a new one.

## Step 3: Resize it

```bash
kubectl -n lab patch pod resize-demo --subresource resize --patch \
  '{"spec":{"containers":[{"name":"main","resources":{"requests":{"cpu":"500m","memory":"128Mi"},"limits":{"cpu":"500m","memory":"128Mi"}}}]}}'
```

**What `--subresource resize` means:** a pod's resources used to be fixed once it was created. Since 1.33, Kubernetes has a separate "resize" door for changing them, which access rules can allow on its own.

## Step 4: Check the files again

```bash
kubectl -n lab exec resize-demo -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max
kubectl -n lab get pod resize-demo -o jsonpath='{.status.containerStatuses[0].containerID}  restarts={.status.containerStatuses[0].restartCount}{"\n"}'
```

```output
50000 100000
134217728
containerd://3f9c…  restarts=0
```

**What it means:** the limits are now 500m and 128 MiB, the container ID is the same, and the restart count is still 0. The kubelet asked the container runtime to rewrite the files of the running container. The process inside never noticed.

## Things worth knowing

- `.spec` shows what you asked for; `.status.containerStatuses[0].resources` shows what's actually been applied. While they differ, the pod has a `PodResizeInProgress` condition.
- If the node doesn't have room, the resize waits with a `PodResizePending` condition.
- The QoS class can't change during a resize, which is why this example raises requests and limits together.
- `resizePolicy` can ask for a restart instead, for apps that only read their memory size at startup, such as a JVM with a fixed heap.

## Clean up

```bash
kubectl -n lab delete pod resize-demo
```

## Shortcut

`make 13-in-place-resize` runs all of this and checks the new values, the restart count and the container ID.
