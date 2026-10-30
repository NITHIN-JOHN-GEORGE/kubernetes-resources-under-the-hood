#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod follow-me labs/10-follow-one-pod-down/
cid=$(kubectl -n "$NS" get pod follow-me -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's#containerd://##')
spec=$(on_node "crictl inspect $cid" 2>/dev/null)
echo "$spec" | grep -q '"shares": 256' && pass "the runtime spec asks for 256 CPU shares (250m)" || fail "expected shares 256 in crictl inspect"
echo "$spec" | grep -q '"quota": 50000' && pass "and a quota of 50000 per 100000 (500m)" || fail "expected quota 50000"
[ "$(on_node "systemctl show cri-containerd-$cid.scope -p CPUQuotaPerSecUSec --value")" = 500ms ] && pass "systemd holds the limit as 500ms per second" || fail "expected CPUQuotaPerSecUSec=500ms"
[ "$(cg follow-me cpu.max)" = "50000 100000" ] && pass "cpu.max is 50000 100000" || fail "cpu.max should be 50000 100000"
[ "$(cg follow-me memory.max)" = 134217728 ] && pass "memory.max is 134217728" || fail "memory.max should be 134217728"
[ "$(cg follow-me memory.min)" = 0 ] && pass "memory.min is 0: the memory request isn't protected by the kernel" || fail "memory.min should be 0"
[ "$(kubectl -n "$NS" exec follow-me -- cat /proc/self/cgroup)" = "0::/" ] && pass "inside the pod, the cgroup path reads 0::/" || fail "expected 0::/ inside the pod"
finish
