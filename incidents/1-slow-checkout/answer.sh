#!/usr/bin/env bash
# Check an answer for incident 1 and explain what was going on.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *throttl*|*cpu*limit*|*quota*) pass "Correct: CPU throttling." ;;
  "") echo "Usage: make answer-1 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-1"; exit 1 ;;
esac

title "What was happening"
p0=$(cg_key checkout-api cpu.stat nr_periods); t0=$(cg_key checkout-api cpu.stat nr_throttled); sleep 5
p1=$(cg_key checkout-api cpu.stat nr_periods); t1=$(cg_key checkout-api cpu.stat nr_throttled)
echo "  In the last 5 s: throttled in $(( t1 - t0 )) of $(( p1 - p0 )) periods   (cpu.stat)"
cat <<'MSG'

  Each request runs 4 worker processes at once, each needing about 40 ms of CPU: 160 ms in total.
  The limit is 200m, which cpu.max turns into 20 ms of CPU per 100 ms period.
  4 processes spend those 20 ms in about 5 ms, then the whole container waits for the next period.
  160 ms of work at 20 ms per period takes 8 periods: about 800 ms. The average CPU still looks
  low, because the pod sleeps for a second between requests.

  The fix: give it enough quota for its burst (or drop the CPU limit and rely on the request).
  Let's raise it to 1 CPU, live, with an in-place resize:
MSG
step "kubectl -n $NS patch pod checkout-api --subresource resize ... (limits.cpu: 1)"
kubectl -n "$NS" patch pod checkout-api --subresource resize --patch \
  '{"spec":{"containers":[{"name":"main","resources":{"requests":{"cpu":"1"},"limits":{"cpu":"1"}}}]}}' >/dev/null 2>&1 \
  || { note "  (resize needs Kubernetes 1.33+; skip this part on older clusters)"; exit 0; }
sleep 6
step "kubectl -n $NS logs checkout-api --tail=3"
kubectl -n "$NS" logs checkout-api --tail=3 | sed 's/^/  /'
note "  Same code, same node. Only cpu.max changed. Clean up with: make incident-clean"
