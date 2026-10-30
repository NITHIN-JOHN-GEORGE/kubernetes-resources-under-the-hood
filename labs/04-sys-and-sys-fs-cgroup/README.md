# 04 · /sys and /sys/fs/cgroup

> **Runs on:** Docker only · **Time:** 5 minutes · **Blog:** [chapter 4](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#4-sys-the-kernels-settings-panel)
>
> **You'll learn:** where the kernel keeps its settings, and where resource limits live.

## The question

`/proc` tells us what's happening. Where are the settings?

## Predict first

<details>
<summary>Run <code>mount | grep cgroup</code> inside a container. What filesystem type will it show, and can you write to it?</summary>

<code>cgroup2</code>, mounted read-only (<code>ro</code>). Docker doesn't let a normal container change its own limits. You'll write cgroup files on a lab node in lab 08.
</details>

## Steps

```bash
docker run -d --name lab-box --cpus=0.5 --memory=128m ubuntu sleep infinity
```

`/sys` holds the kernel's settings, usually one value per file:

```bash
docker exec lab-box ls /sys
docker exec lab-box cat /sys/devices/system/cpu/online
docker exec lab-box ls /sys/fs
```

```text
block  bus  class  dev  devices  firmware  fs  kernel  module
0-9
9p  bpf  btrfs  cgroup  erofs  ext4  f2fs  fuse  nfs  pstore  virtiofs  xfs
```

(`0-9` means ten CPUs on my machine; yours will match your Docker settings.)

Now the folder this whole lab is about:

```bash
docker exec lab-box sh -c 'mount | grep cgroup'
docker exec lab-box stat -fc %T /sys/fs/cgroup
```

```text
cgroup on /sys/fs/cgroup type cgroup2 (ro,nosuid,nodev,noexec,relatime)
cgroup2fs
```

## What happened

`type cgroup2` (or `cgroup2fs`) means **cgroups version 2**, the only version these labs use. If you saw `tmpfs` instead, the machine is on version 1. `ro` means read-only: inside a container you can read your limits but not change them.

> **In one line:** `/sys` holds the kernel's settings, and `/sys/fs/cgroup` is where CPU and memory limits live.

Check your work: `make check LAB=04`

## Clean up

```bash
docker rm -f lab-box
```

**Next:** [lab 05 · cpu.max and cpu.weight](../05-cpu-max-and-cpu-weight/)
