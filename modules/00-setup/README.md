# 00 · cgroups v2 on a Kubernetes node

**What you'll learn:** what a cgroup actually is on a Linux machine, and the folder tree the kubelet builds for pods. No pods yet, you're just looking around a node.

**Time:** about 5 minutes. **You need:** the cluster from `make cluster`. Run every command from the repo folder.

---

## Step 1: Step onto the node

A kind node is just a Docker container on your laptop. `docker exec` runs a command inside it, which is the same as SSH-ing into a node in a real cluster and running it there.

```bash
docker exec under-the-hood-worker hostname
```

```output
under-the-hood-worker
```

Every `docker exec under-the-hood-worker ...` command in this lab means "run this on the worker node".

## Step 2: Check which cgroup version the node uses

```bash
docker exec under-the-hood-worker stat -fc %T /sys/fs/cgroup/
```

```output
cgroup2fs
```

**What `/sys/fs/cgroup` is:** it looks like a folder full of files, but nothing in it is stored on disk. It's a window into the kernel. When you `cat` a file there, the kernel answers with a live value ("this group has used 3.2 seconds of CPU"). When you write to one, you change a setting ("this group may use at most 128 MiB"). The same trick powers `/proc`, which you'll meet in module 05.

**What `stat -fc %T` does:** it prints the *type* of filesystem mounted at that path. `cgroup2fs` means cgroups **v2**, the modern layout where everything lives in one tree. If you see `tmpfs`, the node is on the older v1 layout, which this lab doesn't cover.

## Step 3: See which "dials" the kernel offers

```bash
docker exec under-the-hood-worker cat /sys/fs/cgroup/cgroup.controllers
```

You'll see a list like `cpuset cpu io memory hugetlb pids rdma misc` (the exact list depends on your kernel).

**What it means:** each word is a *controller*, a part of the kernel that can measure and limit one kind of resource for a group of processes:

| Controller | What it controls | Lessons |
|---|---|---|
| `cpu` | How much CPU time a group gets | 02, 03 |
| `memory` | How much RAM a group may use, and what happens when it runs out | 04 |
| `pids` | How many processes a group may start | 11 |
| `io` | Disk read/write speed | 12 (pressure) |
| `cpuset` | Which CPU cores a group may run on | not covered |

## Step 4: Ask the kubelet how it uses cgroups

The kubelet exposes its live configuration through the API server:

```bash
kubectl get --raw /api/v1/nodes/under-the-hood-worker/proxy/configz | grep -o '"cgroup[A-Za-z]*":"[^"]*"'
```

```output
"cgroupDriver":"systemd"
"cgroupRoot":"/kubelet"
```

**What it means:**

- **`cgroupDriver: systemd`**: the kubelet doesn't create cgroup folders directly. It asks systemd, the program that manages services on most Linux machines, to do it. That's why the folders have systemd-style names ending in `.slice` (a group of groups) and `.scope` (a group of processes started from outside, like a container).
- **`cgroupRoot: /kubelet`**: kind tells the kubelet to keep its tree under `/kubelet`, so every name gets a `kubelet-` prefix. On a normal node, this is empty and the tree starts at `/sys/fs/cgroup/kubepods.slice`.

## Step 5: Look at the pod tree

```bash
docker exec under-the-hood-worker ls /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/
```

Among the files, you'll see two folders:

```text
kubelet-kubepods-besteffort.slice
kubelet-kubepods-burstable.slice
```

**What it means:** this folder is the box that holds *every* pod on the node. Inside it, pods are sorted into boxes by their QoS class (module 05). Guaranteed pods get a folder directly in here; Burstable and BestEffort pods go into these two sub-boxes. Inside each pod's folder, there's one more folder per container. It's boxes inside boxes, and **a box can never use more than the box it sits in**.

## Step 6: Read the ceiling for all pods

```bash
docker exec under-the-hood-worker cat /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/memory.max
```

```output
8321515520
```

(Your number depends on how much memory Docker has.)

**What `memory.max` is:** the most memory, in bytes, that everything inside this box may use together. Here it's about 7.75 GiB, roughly all the memory Docker gave the node, because kind reserves nothing for the system. Module 06 explains how this number is chosen.

## Summary

| Path | What it is |
|---|---|
| `/sys/fs/cgroup/` | The kernel's cgroup tree, shown as files |
| `cgroup.controllers` | Which kinds of resources can be controlled |
| `…/kubelet-kubepods.slice/` | The box holding every pod on the node |
| `…-burstable.slice/`, `…-besteffort.slice/` | Sub-boxes per QoS class |
| `memory.max` | Most memory, in bytes, this box may use |

## Shortcut

`make 00-setup` runs these checks in one go and confirms the node is on cgroups v2 with the systemd driver. If it fails on Windows, it prints the WSL2 setting to fix it.
