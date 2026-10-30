#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod weight-low labs/13-requests-become-weights/; need_pod weight-high labs/13-requests-become-weights/
[ "$(cg weight-low cpu.max)" = "max 100000" ] && [ "$(cg weight-high cpu.max)" = "max 100000" ] && pass "neither pod has a CPU limit" || fail "both pods should have cpu.max 'max 100000'"
pl=$(on_node "cat $(pod_cgroup_dir weight-low)/cpu.weight"); ph=$(on_node "cat $(pod_cgroup_dir weight-high)/cpu.weight")
[ "${ph:-0}" -gt "${pl:-0}" ] && pass "pod cgroup weights: weight-low $pl, weight-high $ph" || fail "weight-high's pod cgroup should have the higher weight"
l=$(pod_millicores weight-low 5); h=$(pod_millicores weight-high 5)
echo "  weight-low ${l}m, weight-high ${h}m (each measured over 5 s)"
[ "$l" -gt 0 ] && [ "$h" -ge $(( l * 4 )) ] && pass "weight-high got at least 4x the CPU" || fail "weight-high should get several times more CPU"
finish
