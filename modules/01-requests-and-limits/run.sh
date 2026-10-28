#!/usr/bin/env bash
# Module 01: how requests and limits become cgroup files.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=requests-limits

cleanup_on_exit module=01
title "Module 01: requests and limits become cgroup files"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
apply "$dir/pod.yaml"
wait_ready "$pod"

step "kubectl -n $NS exec $pod -- cat /sys/fs/cgroup/{cpu.weight,cpu.max,memory.max,memory.min}"
show_cg "$pod" cpu.weight
show_cg "$pod" cpu.max
show_cg "$pod" memory.max
show_cg "$pod" memory.min
note "requests.cpu 250m  -> cpu.weight (relative share, only matters under contention)"
note "limits.cpu   500m  -> cpu.max '50000 100000' (50ms of CPU time per 100ms period)"
note "limits.memory 128Mi -> memory.max 134217728 bytes (hard ceiling, OOM kill above it)"
note "requests.memory    -> not written anywhere by default; the scheduler uses it, memory.min stays 0"

step "pod-level cgroup on the node: $(pod_cgroup_dir "$pod")"
pdir="$(pod_cgroup_dir "$pod")"
on_node "printf '  %-12s %s\n' cpu.max \"\$(cat $pdir/cpu.max)\"; printf '  %-12s %s\n' memory.max \"\$(cat $pdir/memory.max)\""
note "The pod slice carries the sum of its containers' limits (here a single container)."

title "Checks"
cpumax="$(cg "$pod" cpu.max)"; memmax="$(cg "$pod" memory.max)"; weight="$(cg "$pod" cpu.weight)"; memmin="$(cg "$pod" memory.min)"
[ "$cpumax" = "50000 100000" ] && pass "cpu.max is '50000 100000'" || fail "cpu.max is '$cpumax', expected '50000 100000'"
[ "$memmax" = "134217728" ] && pass "memory.max is 134217728 (128Mi)" || fail "memory.max is '$memmax', expected 134217728"
[ "$weight" -gt 1 ] 2>/dev/null && pass "cpu.weight is set ($weight)" || fail "cpu.weight looks wrong: '$weight'"
[ "$memmin" = "0" ] && pass "memory.min is 0: the memory request is not enforced by the kernel" || note "memory.min is $memmin (Memory QoS feature gate may be on)"

finish
