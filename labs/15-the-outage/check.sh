#!/usr/bin/env bash
# Read-only: did the outage happen, and (after the fix step) did it stop?
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" get deployment serve >/dev/null 2>&1 || { fail "deployment serve not found. Run the README's first step."; finish; }
# Only count probe failures from this run (events stay around for an hour), and not the
# "connection refused" ones from a pod that is still starting up.
since=$(kubectl -n "$NS" get pod load -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
[ -n "$since" ] || { fail "the load pod isn't running. Run the load step."; finish; }
ev=$(kubectl -n "$NS" get events --field-selector reason=Unhealthy -o jsonpath='{range .items[*]}{.lastTimestamp}{.eventTime} {.message}{"\n"}{end}' 2>/dev/null \
  | awk -v s="$since" '$1 >= s' | grep -v "connection refused")
r=$(printf '%s\n' "$ev" | grep -c "Readiness probe failed")
l=$(printf '%s\n' "$ev" | grep -c "Liveness probe failed")
[ "$r" -gt 0 ] && pass "readiness probes timed out under load ($r times): pods dropped out of the Service" || fail "no readiness timeouts under load yet. Give it a minute."
[ "$l" -gt 0 ] && pass "liveness probes timed out under load ($l times)" || fail "no liveness timeouts under load yet"
lim=$(kubectl -n "$NS" get deployment serve -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')
if [ "$lim" = 2 ]; then
  P=$(kubectl -n "$NS" get pod -l app=serve -o jsonpath='{.items[0].metadata.name}')
  r=$(kubectl -n "$NS" get pod "$P" -o jsonpath='{.status.containerStatuses[0].restartCount}')
  [ "$r" = 0 ] && pass "with a 2 CPU limit, $P hasn't restarted" || fail "$P restarted $r times even with the bigger limit"
else
  note "  (run the fix step to raise the limit to 2 CPUs, then check again)"
fi
finish
