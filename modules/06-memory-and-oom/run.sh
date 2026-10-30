#!/usr/bin/env bash
# Module 06: crossing memory.max triggers the kernel OOM killer inside the cgroup.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=memory-hog

cleanup_on_exit module=06
title "Module 06: memory limits and OOM kills"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
apply "$dir/pod.yaml"

note "Waiting for the first OOM kill (the container allocates 10 MiB every 0.3s against a 64Mi limit)..."
reason=""
for _ in $(seq 1 90); do
  reason="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || true)"
  [ -n "$reason" ] && break
  sleep 2
done

step "kubectl -n $NS logs $pod --previous | tail -3"
kubectl -n "$NS" logs "$pod" --previous 2>/dev/null | tail -3 || true
note "It never reaches 64 MiB of Python objects: the interpreter itself also counts against the limit."

step "kubectl -n $NS get pod $pod -o jsonpath=... (last termination)"
kubectl -n "$NS" get pod "$pod" -o jsonpath='{range .status.containerStatuses[0]}  reason={.lastState.terminated.reason}  exitCode={.lastState.terminated.exitCode}  restarts={.restartCount}{"\n"}{end}'
note "exitCode 137 = 128 + 9: the process was killed with SIGKILL by the kernel."

pdir="$(pod_cgroup_dir "$pod")"
step "docker exec $WORKER cat $pdir/memory.events"
on_node "cat $pdir/memory.events" | sed 's/^/  /'
note "memory.events at the pod level is hierarchical: it counts OOM kills in any of the pod's containers."
note "'max' counts how often usage hit memory.max; 'oom_kill' counts processes the kernel killed."

step "docker exec $WORKER cat $pdir/memory.max"
on_node "cat $pdir/memory.max" | sed 's/^/  /'

title "Checks"
[ "$reason" = "OOMKilled" ] && pass "container was OOMKilled" || fail "expected OOMKilled, got '${reason:-nothing}'"
kills="$(on_node "awk '\$1==\"oom_kill\" {print \$2}' $pdir/memory.events")"
[ "${kills:-0}" -ge 1 ] && pass "memory.events records $kills oom_kill(s)" || fail "memory.events shows no oom_kill"
[ "$(on_node "cat $pdir/memory.max")" = "67108864" ] && pass "pod memory.max is 67108864 (64Mi)" || fail "unexpected pod memory.max"

finish
