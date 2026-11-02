#!/usr/bin/env bash
# Check an answer for incident 4 and explain what was going on, one step at a time.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *neighbo*|*noisy*|*contention*|*request*|*limit*|*batch*) pass "Correct: noisy neighbours. The node is full, not the controller's budget." ;;
  "") echo "Usage: make answer-4 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-4"; exit 1 ;;
esac
kubectl -n "$NS" get pod controller >/dev/null 2>&1 || { echo "controller isn't running. Start it with: make incident-4"; exit 1; }

signals() {
  p0=$(cg_key controller cpu.stat nr_periods); t0=$(cg_key controller cpu.stat nr_throttled); sleep 5
  p1=$(cg_key controller cpu.stat nr_periods); t1=$(cg_key controller cpu.stat nr_throttled)
  echo "  1. throttled (controller's cpu.stat):       $(( t1 - t0 )) of $(( p1 - p0 )) periods"
  echo "  2. waiting   (controller's cpu.pressure):   $(cg controller cpu.pressure | head -n1)"
  echo "  3. node      (/proc/pressure/cpu):          $(on_node 'head -n1 /proc/pressure/cpu')"
}

stage "1. The evidence"
signals
echo
note "  Waiting, but not throttled: the controller's own limit isn't what stops it."
echo
run kubectl -n "$NS" get pods -l incident -o custom-columns=NAME:.metadata.name,REQUEST:.spec.containers[0].resources.requests.cpu,LIMIT:.spec.containers[0].resources.limits.cpu
echo "  The node has $(kubectl get node "$WORKER" -o jsonpath='{.status.capacity.cpu}') CPUs."
echo
note "  The same signals as Prometheus metrics, from the kubelet:"
m=$(kubectl get --raw "/api/v1/nodes/$WORKER/proxy/metrics/cadvisor" 2>/dev/null \
  | grep -E '^container_pressure_cpu_[a-z_]+\{' | grep 'pod="controller"' | grep -v 'container=""' | head -n2)
if [ -n "$m" ]; then echo "$m" | sed 's/^/    /'; else note "    (this kubelet doesn't export PSI metrics yet)"; fi
pause

stage "2. Why it happened"
cat <<'MSG'
  1. Each batch job's CPU limit is far above the node's size. A wallet that big never empties,
     so nothing is throttled, and each job can grab every core whenever it likes.
  2. Their requests are tiny, so the scheduler happily put them all on one node.
  3. Together they keep every core busy. The controller has budget left, but no free core:
     its workers queue behind dozens of batch threads, and each request takes longer.
  4. A pod's cpu.pressure counts that waiting. cpu.stat doesn't, because the controller
     never ran out of its own budget.
MSG
pause

stage "3. The fix, live"
note "  Bring the batch jobs' limits back to reality: 1 CPU each, with an in-place resize."
note "  (Other fixes: realistic requests, or keeping batch jobs on their own nodes.)"
echo
note "  Before:"
kubectl -n "$NS" logs controller --tail=2 | sed 's/^/    /'
for p in batch-1 batch-2 batch-3; do
  step "kubectl patch pod $p --subresource resize ...   (requests.cpu: 1, limits.cpu: 1)"
  kubectl -n "$NS" patch pod "$p" --subresource resize --patch \
    '{"spec":{"containers":[{"name":"main","resources":{"requests":{"cpu":"1"},"limits":{"cpu":"1"}}}]}}' >/dev/null 2>&1 \
    || { note "  (resize needs Kubernetes 1.33+)"; exit 0; }
done
note "  Waiting 20 seconds for the 10-second averages to catch up..."
sleep 20
echo
note "  After (same pods, same node, only the batch jobs' limits changed):"
kubectl -n "$NS" logs controller --tail=2 | sed 's/^/    /'
echo
signals
pause

stage "4. Remember"
cat <<'MSG'
  Throttling means your own budget ran out. Pressure means you waited, for any reason.
  Waiting without throttling points at your neighbours: limits bigger than the node,
  requests that are too small, and bursty jobs packed next to latency-sensitive ones.

  Revisit: labs/13-requests-become-weights and labs/19-metrics-and-psi.   Clean up: make reset
MSG
