#!/usr/bin/env bash
# Module 00: the node's cgroup v2 tree before any lab pods exist.
source "$(dirname "$0")/../../lib/common.sh"

title "Module 00: cgroups v2 on a Kubernetes node"

step "docker exec $WORKER stat -fc %T /sys/fs/cgroup/"
fstype="$(on_node 'stat -fc %T /sys/fs/cgroup/')"
echo "$fstype"
note "cgroup2fs means the unified cgroups v2 hierarchy. tmpfs would mean the old v1 layout."

step "docker exec $WORKER cat /sys/fs/cgroup/cgroup.controllers"
on_node 'cat /sys/fs/cgroup/cgroup.controllers'
note "These are the controllers the kernel offers: cpu, memory, io, pids and more."

step "kubectl get --raw /api/v1/nodes/$WORKER/proxy/configz | cgroupDriver, cgroupRoot"
configz="$(kubectl get --raw "/api/v1/nodes/$WORKER/proxy/configz")"
driver="$(printf '%s' "$configz" | grep -o '"cgroupDriver":"[a-z]*"' | cut -d'"' -f4)"
croot="$(printf '%s' "$configz" | grep -o '"cgroupRoot":"[^"]*"' | cut -d'"' -f4)"
echo "cgroupDriver: $driver"
echo "cgroupRoot:   ${croot:-/ (default)}"
note "kind sets cgroupRoot=/kubelet so the kubelet's tree sits under kubelet.slice. On a normal node it is kubepods.slice."

step "docker exec $WORKER find /sys/fs/cgroup -maxdepth 2 -name '*kubepods.slice'"
root="$(kubepods_root)"
echo "${root:-not found}"

step "docker exec $WORKER ls -d $root/*/"
[ -n "$root" ] && on_node "ls -d $root/*/" | sed 's#^#  #'
note "One slice per QoS class (burstable, besteffort), plus one slice per Guaranteed pod directly under the root."

step "pod tree limits (the ceiling for every pod on this node)"
[ -n "$root" ] && on_node "for f in cpu.max memory.max cpu.weight; do printf '  %-12s %s\\n' \$f \"\$(cat $root/\$f)\"; done"
note "memory.max here is node allocatable memory: the most all pods together may use."

title "Checks"
if [ "$fstype" = "cgroup2fs" ]; then pass "node uses cgroups v2"
else
  fail "node is not on cgroups v2 (got $fstype)"
  note "Windows/WSL2: add 'kernelCommandLine = cgroup_no_v1=all' under [wsl2] in %UserProfile%\\.wslconfig, run 'wsl --shutdown', restart Docker Desktop, then recreate the cluster."
fi
if [ -n "$root" ]; then pass "found the kubelet's pod tree at ${root#/sys/fs/cgroup/}"; else fail "could not find the kubelet's pod tree"; fi
if [ "$driver" = "systemd" ]; then pass "kubelet uses the systemd cgroup driver"; else fail "expected the systemd cgroup driver, got '$driver'"; fi
finish
