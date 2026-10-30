#!/usr/bin/env bash
# Check an answer for incident 3 and explain what was going on, one step at a time.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *spike*|*peak*|*burst*|*report*|*short*) pass "Correct: a short memory spike, between dashboard samples." ;;
  "") echo "Usage: make answer-3 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-3"; exit 1 ;;
esac
kubectl -n "$NS" get pod report-worker >/dev/null 2>&1 || { echo "report-worker isn't running. Start it with: make incident-3"; exit 1; }
pdir="$(pod_cgroup_dir report-worker)"

stage "1. The evidence"
echo "  How it died:  $(kubectl -n "$NS" get pod report-worker -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}, exit code {.status.containerStatuses[0].lastState.terminated.exitCode}, restarts: {.status.containerStatuses[0].restartCount}')"
echo "  memory.peak:  $(( $(on_node "cat $pdir/memory.peak") / 1048576 )) MiB   (memory.max: 256 MiB)"
echo "  memory.events:"; on_node "grep -E '^(max|oom_kill) ' $pdir/memory.events" | sed 's/^/    /'
echo
note "  The kernel saw the pod hit its 256 MiB ceiling and killed it. The graph never did."
echo
note "  The last lines it logged:"
kubectl -n "$NS" logs report-worker --tail=3 2>/dev/null | sed 's/^/    /'
pause

stage "2. Why it happened"
cat <<'MSG'
  1. The worker holds a 100 MiB cache all the time. That's the "about 40%" on the graph.
  2. Every 20 seconds it builds a report that needs another 200 MiB, for well under a second.
  3. 100 + 200 MiB is more than 256 MiB, so the kernel OOM-kills it in the middle of the report.
  4. The spike is too short for a dashboard that samples every 15 seconds to catch.
     memory.peak and memory.events do: the kernel doesn't sample, it counts.
MSG
pause

stage "3. The fix, live"
note "  Size the limit for the peak, not the average: 100 + 200 MiB plus headroom, so 320Mi."
note "  (Or change the code so the report isn't built in memory all at once.)"
before=$(kubectl -n "$NS" get pod report-worker -o jsonpath='{.status.containerStatuses[0].restartCount}')
step "kubectl patch pod report-worker --subresource resize ...   (memory: 320Mi)"
kubectl -n "$NS" patch pod report-worker --subresource resize --patch \
  '{"spec":{"containers":[{"name":"main","resources":{"requests":{"memory":"320Mi"},"limits":{"memory":"320Mi"}}}]}}' >/dev/null 2>&1 \
  || { note "  (resize needs Kubernetes 1.33+)"; exit 0; }
note "  Waiting 45 seconds: two more reports..."
sleep 45
after=$(kubectl -n "$NS" get pod report-worker -o jsonpath='{.status.containerStatuses[0].restartCount}')
echo "  restarts before: $before   after: $after"
kubectl -n "$NS" logs report-worker --tail=2 | sed 's/^/    /'
note "  Same code. Reports now finish, and the pod stops restarting."
pause

stage "4. Remember"
cat <<'MSG'
  Dashboards sample; the kernel doesn't. When a pod is OOM-killed "below its limit",
  check memory.peak and memory.events, and size limits for the peak.

  Revisit: labs/16-memory-limits-and-oom and labs/17-not-all-memory-is-equal.   Clean up: make reset
MSG
