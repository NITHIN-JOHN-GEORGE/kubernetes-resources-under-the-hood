#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod prio-high labs/E3-priority-and-preemption/
[ "$(kubectl -n "$NS" get pod prio-high -o jsonpath='{.status.phase}')" = Running ] && pass "prio-high is running" || fail "prio-high should be running"
kubectl -n "$NS" get events --field-selector involvedObject.name=prio-low --no-headers 2>/dev/null | grep -q Preempted && pass "prio-low was preempted to make room" || fail "expected a Preempted event for prio-low"
finish
