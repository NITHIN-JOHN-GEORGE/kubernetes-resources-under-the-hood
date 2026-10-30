#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod mem-lab labs/17-not-all-memory-is-equal/
ev="$(pod_cgroup_dir mem-lab)/memory.events"
mx=$(on_node "awk '\$1==\"max\"{print \$2}' $ev"); gk=$(on_node "awk '\$1==\"oom_group_kill\"{print \$2}' $ev")
[ "${mx:-0}" -gt 0 ] && pass "the cgroup hit memory.max $mx times (reclaim)" || fail "memory.events 'max' should be above 0 after the cache step"
[ "${gk:-0}" -ge 1 ] && pass "the alloc step ended in an OOM group kill" || fail "expected oom_group_kill 1 after the alloc step"
[ "$(kubectl -n "$NS" get pod mem-lab -o jsonpath='{.status.containerStatuses[0].restartCount}')" -ge 1 ] && pass "the container was restarted" || fail "mem-lab should have restarted once"
pk=$(on_node "cat $(pod_cgroup_dir mem-lab)/memory.peak")
[ "${pk:-0}" -ge 100000000 ] && pass "memory.peak remembers $(( pk / 1048576 )) MiB" || fail "memory.peak should be near the 128Mi limit"
finish
