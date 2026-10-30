#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod memory-hog labs/16-memory-limits-and-oom/
[ "$(kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}')" = OOMKilled ] && pass "the last termination was OOMKilled" || fail "expected lastState OOMKilled (give it 20 seconds)"
[ "$(kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}')" = 137 ] && pass "exit code 137" || fail "expected exit code 137"
k=$(on_node "awk '\$1==\"oom_kill\"{print \$2}' $(pod_cgroup_dir memory-hog)/memory.events")
[ "${k:-0}" -ge 1 ] && pass "memory.events counts $k OOM kill(s)" || fail "memory.events should show oom_kill"
finish
