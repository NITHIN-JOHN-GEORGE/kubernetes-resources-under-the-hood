# 07 · What a container is

> **Runs on:** Docker only · **Time:** 10 minutes · **Blog:** [chapter 7](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#7-so-what-is-a-container)
>
> **You'll learn:** that a container is ordinary processes with namespaces (what they see) and cgroups (what they get).

## The question

Is there a "container" anywhere in the kernel?

## Predict first

<details>
<summary>Start two containers, each running <code>sleep</code>. What PID will <code>sleep</code> have in each one?</summary>

PID 1 in both. Each container has its own PID namespace, so each sees its own process list. From outside, they're two ordinary processes with ordinary PIDs.
</details>

## Steps

Start two containers from the `lab-tools` image:

```bash
docker run -d --name lab-box  lab-tools:1.0 sleep infinity
docker run -d --name lab-box2 lab-tools:1.0 sleep infinity
```

From inside, each one sees a `sleep` as PID 1, and a cgroup path of just `/`:

```bash
docker exec lab-box  cat /proc/1/comm /proc/self/cgroup
docker exec lab-box2 cat /proc/1/comm /proc/self/cgroup
```

Now look from outside. Docker knows the real PID of each container's `sleep` on the Docker host. A helper container that shares the host's process list (`--pid=host`) and cgroup view (`--cgroupns=host`) can read it:

```bash
PID=$(docker inspect lab-box --format '{{.State.Pid}}')
echo "lab-box's sleep is PID $PID on the Docker host"
docker run --rm --pid=host --cgroupns=host lab-tools:1.0 cat /proc/$PID/comm /proc/$PID/cgroup
```

Same `sleep`, a different PID, and a long cgroup path instead of `/`.

## What happened

| Kernel feature | Controls | What you saw |
|---|---|---|
| **PID namespace** | Which processes it can **see** | `sleep` is PID 1 inside, a normal PID outside |
| **cgroup namespace** | Which part of the cgroup tree it sees | `/` inside, the full path outside |
| **cgroups** | How much it can **use** | The limits from labs 05 and 06 |

The kernel has no "container" object. A container runtime puts ordinary processes into namespaces and cgroups and starts them.

> **In one line:** a container is processes with namespaces (what they see) and cgroups (what they get).

Check your work: `make check LAB=07`

## Clean up

```bash
docker rm -f lab-box lab-box2
```

**Next:** [lab 08 · Build a cgroup by hand](../08-build-a-cgroup-by-hand/) (this one needs the cluster: `make cluster`)
