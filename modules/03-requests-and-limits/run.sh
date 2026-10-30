#!/usr/bin/env bash
# Module 03: how requests and limits become cgroup files.
# This script runs the same steps as README.md, in the same order, and checks the results.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=requests-limits

cleanup_on_exit module=03
title "Module 03: requests and limits become cgroup files"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true

note "Step 2: create the pod (requests 250m/64Mi, limits 500m/128Mi)"
apply "$dir/pod.yaml"
wait_ready "$pod"

note ""
note "Step 3: the CPU limit"
step "kubectl -n $NS exec $pod -- cat /sys/fs/cgroup/cpu.max"
cpumax="$(cg "$pod" cpu.max)"; echo "  $cpumax"
note "  limits.cpu 500m -> 50ms of CPU in every 100ms"

note ""
note "Step 4: the memory limit"
step "kubectl -n $NS exec $pod -- cat /sys/fs/cgroup/memory.max"
memmax="$(cg "$pod" memory.max)"; echo "  $memmax"
note "  limits.memory 128Mi -> 134217728 bytes; above this the kernel kills the container"

note ""
note "Step 5: the CPU request"
step "kubectl -n $NS exec $pod -- cat /sys/fs/cgroup/cpu.weight"
weight="$(cg "$pod" cpu.weight)"; echo "  $weight"
note "  requests.cpu 250m -> a weight, only used when CPUs are busy"

note ""
note "Step 6: the memory request"
step "kubectl -n $NS exec $pod -- cat /sys/fs/cgroup/memory.min"
memmin="$(cg "$pod" memory.min)"; echo "  $memmin"
note "  requests.memory 64Mi -> nothing; only the scheduler uses it"

note ""
note "Step 7: the same limits on the pod's folder, seen from the node"
pdir="$(pod_cgroup_dir "$pod")"
step "docker exec $WORKER cat \$POD_DIR/cpu.max \$POD_DIR/memory.max"
echo "  POD_DIR=${pdir#/sys/fs/cgroup/}"
on_node "cat $pdir/cpu.max $pdir/memory.max" | sed 's/^/  /'

title "Checks"
[ "$cpumax" = "50000 100000" ] && pass "cpu.max is '50000 100000'" || fail "cpu.max is '$cpumax', expected '50000 100000'"
[ "$memmax" = "134217728" ] && pass "memory.max is 134217728 (128Mi)" || fail "memory.max is '$memmax', expected 134217728"
[ "$weight" -gt 1 ] 2>/dev/null && pass "cpu.weight is set ($weight)" || fail "cpu.weight looks wrong: '$weight'"
[ "$memmin" = "0" ] && pass "memory.min is 0: the memory request is not enforced by the kernel" || note "memory.min is $memmin (Memory QoS feature gate may be on)"

finish
