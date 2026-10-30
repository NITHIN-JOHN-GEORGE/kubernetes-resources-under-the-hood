#!/usr/bin/env bash
# Check an answer for incident 1 and explain what was going on, one step at a time.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *throttl*|*cpu*limit*|*quota*) pass "Correct: CPU throttling." ;;
  "") echo "Usage: make answer-1 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-1"; exit 1 ;;
esac
kubectl -n "$NS" get pod checkout-api >/dev/null 2>&1 || { echo "checkout-api isn't running. Start it with: make incident-1"; exit 1; }

stage "1. The evidence"
run kubectl -n "$NS" exec checkout-api -- cat /sys/fs/cgroup/cpu.max
note "  20000 100000: at most 20 ms of CPU in every 100 ms. That's the 200m limit."
echo
p0=$(cg_key checkout-api cpu.stat nr_periods); t0=$(cg_key checkout-api cpu.stat nr_throttled); sleep 5
p1=$(cg_key checkout-api cpu.stat nr_periods); t1=$(cg_key checkout-api cpu.stat nr_throttled)
echo "  cpu.stat over 5 seconds: throttled in $(( t1 - t0 )) of $(( p1 - p0 )) periods with work to do."
note "  Whenever there's a request, the pod runs out of budget and waits."
pause

stage "2. Why it happened"
cat <<'MSG'
  1. A request starts 4 processes at once, each needing about 40 ms of CPU: 160 ms in total.
  2. Together they spend the 20 ms budget in about 5 ms of real time.
  3. Then the whole container waits for the next 100 ms period. Nothing runs, even with idle CPUs.
  4. 160 ms of work at 20 ms per period takes 8 periods: about 800 ms per request.
  5. Between requests the pod sleeps, so the AVERAGE stays under the limit. The graph looks fine.
MSG
pause

stage "3. The fix, live"
note "  Give it enough budget for its burst: raise the limit to 1 CPU, with an in-place resize."
note "  (Or drop the CPU limit and rely on the request.)"
echo
note "  Before:"
kubectl -n "$NS" logs checkout-api --tail=2 | sed 's/^/    /'
step "kubectl patch pod checkout-api --subresource resize ...   (limits.cpu: 1)"
kubectl -n "$NS" patch pod checkout-api --subresource resize --patch \
  '{"spec":{"containers":[{"name":"main","resources":{"requests":{"cpu":"1"},"limits":{"cpu":"1"}}}]}}' >/dev/null 2>&1 \
  || { note "  (resize needs Kubernetes 1.33+)"; exit 0; }
sleep 6
note "  After (same code, same node, only cpu.max changed):"
kubectl -n "$NS" logs checkout-api --tail=2 | sed 's/^/    /'
pause

stage "4. Remember"
cat <<'MSG'
  A CPU limit is a budget per 100 ms, shared by every thread. Throttling hides behind
  averages: watch nr_throttled / nr_periods, not average CPU.

  Revisit: labs/14-limits-and-throttling and labs/15-the-outage.   Clean up: make reset
MSG
