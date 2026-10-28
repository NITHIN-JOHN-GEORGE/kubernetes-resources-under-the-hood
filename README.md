<div align="center">

# Kubernetes resources, under the hood

**From YAML to cgroups.** A hands-on lab that shows what requests, limits, QoS classes, priority classes and quotas actually do inside the Linux kernel.

[![Run the lab](https://github.com/NITHIN-JOHN-GEORGE/kubernetes-resources-under-the-hood/actions/workflows/lab.yml/badge.svg)](https://github.com/NITHIN-JOHN-GEORGE/kubernetes-resources-under-the-hood/actions/workflows/lab.yml)
![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![cgroups v2](https://img.shields.io/badge/cgroups-v2-38E8C6?style=flat-square&logo=linux&logoColor=black)
![macOS | Windows](https://img.shields.io/badge/runs_on-macOS_%7C_Windows_WSL2-555?style=flat-square)

</div>

Every `resources:` block you write ends up as a few numbers in files under `/sys/fs/cgroup` on a node. This lab creates a local cluster, runs pods with specific settings, and **reads the real kernel files** so you can watch CPU throttling, OOM kills and QoS decisions happen.

```bash
make cluster
make 02-cpu-throttling
```

```text
  pod            periods          throttled      CPU used (millicores)
  cpu-limited    250              249            200
  cpu-unlimited  -                0              several thousand
PASS cpu-limited was throttled in 249 periods
PASS cpu-unlimited was never throttled
```

Every module cleans up its own pods when it finishes, even if a check fails or you press Ctrl-C.

## Modules

| # | Module | You will see |
|---|---|---|
| 00 | [cgroups v2 on a node](modules/00-setup) | The `kubepods.slice` tree the kubelet builds |
| 01 | [Requests and limits](modules/01-requests-and-limits) | `cpu.weight`, `cpu.max`, `memory.max` written for real |
| 02 | [CPU throttling](modules/02-cpu-throttling) | `nr_throttled` climbing under a limit while the node is idle |
| 03 | [CPU weight under contention](modules/03-cpu-weight) | CPU split in proportion to requests |
| 04 | [Memory limits and OOM kills](modules/04-memory-and-oom) | `OOMKilled`, exit code 137 and `oom_kill` in `memory.events` |
| 05 | [QoS classes](modules/05-qos-classes) | Guaranteed / Burstable / BestEffort slices and `oom_score_adj` |
| 06 | [Node allocatable and reservations](modules/06-node-allocatable) | Capacity vs allocatable, the pod tree's `memory.max`, `Insufficient memory` |
| 07 | [Node-pressure eviction](modules/07-node-pressure-eviction) | Kubelet evicts a BestEffort hog under `MemoryPressure` (changes kubelet config, restored on exit) |
| 08 | [Priority classes and preemption](modules/08-priority-preemption) | A high-priority pod preempts a low-priority one |
| 09 | [ResourceQuota](modules/09-resourcequota) | `must specify` and `exceeded quota` at admission |
| 10 | [LimitRange](modules/10-limitrange) | Injected defaults land in `cpu.max` and `memory.max`; over-max pods rejected |
| 11 | [PIDs and ephemeral storage](modules/11-pids-and-ephemeral-storage) | `pids.max`, refused forks, and eviction for local disk use |
| 12 | [Pressure stall information (PSI)](modules/12-psi) | `cpu.pressure`, `memory.pressure`, `io.pressure` |
| 13 | [In-place pod resize](modules/13-in-place-resize) | `cpu.max` and `memory.max` change with no restart (1.33+) |

Each module has a README with the concept, the expected output and what happens in the kernel, plus automatic checks that print `PASS` or `FAIL`.

## Setup

You need **Docker Desktop**, **kind** and **kubectl**. Give Docker at least **4 CPUs and 6 GB of memory** (Docker Desktop → Settings → Resources).

<details open>
<summary><b>macOS</b></summary>

```bash
brew install kind kubectl
git clone https://github.com/NITHIN-JOHN-GEORGE/kubernetes-resources-under-the-hood.git
cd kubernetes-resources-under-the-hood
make cluster
```

</details>

<details>
<summary><b>Windows (WSL2)</b></summary>

Run everything inside an Ubuntu WSL2 terminal. Docker Desktop must use the WSL2 backend with integration enabled for your distro.

1. Make sure WSL2 uses cgroups v2. Create or edit `%UserProfile%\.wslconfig`:

   ```ini
   [wsl2]
   kernelCommandLine = cgroup_no_v1=all
   ```

   Then run `wsl --shutdown` in PowerShell and restart Docker Desktop.

2. In the Ubuntu terminal:

   ```bash
   sudo apt-get update && sudo apt-get install -y make
   curl -Lo kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x kind && sudo mv kind /usr/local/bin/
   curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
   git clone https://github.com/NITHIN-JOHN-GEORGE/kubernetes-resources-under-the-hood.git
   cd kubernetes-resources-under-the-hood
   make cluster
   ```

</details>

Then run `make 00-setup`. If it reports that the node isn't on cgroups v2, follow the hint it prints.

## Commands

```bash
make help                 # list everything
make <module>             # run one module, e.g. make 04-memory-and-oom
make all                  # run every module in order
KEEP=1 make <module>      # keep the module's pods running so you can explore
make reset                # keep the cluster, remove everything the lab created, undo any kubelet change
make clean                # delete the whole kind cluster (make cluster to start again)
```

## How it reads kernel files

- **From inside a container:** with cgroups v2 each container sees its own cgroup at `/sys/fs/cgroup`, so `kubectl exec <pod> -- cat /sys/fs/cgroup/cpu.max` shows that container's limit.
- **From the node:** a kind node is a Docker container, so `docker exec under-the-hood-worker cat /sys/fs/cgroup/kubepods.slice/...` reads the pod and QoS slices directly.

## Further reading

- Blog: [Cgroups: A Deep Dive into Resource Management in Kubernetes](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/), the beginner-friendly walkthrough of every module, with diagrams
- [Kubernetes docs: Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Linux kernel docs: Control Group v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)

## License

[Apache 2.0](LICENSE)
