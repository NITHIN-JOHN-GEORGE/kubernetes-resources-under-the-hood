#!/usr/bin/env bash
# Incident 1: checkout is slow, but the CPU graph looks fine.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found >/dev/null 2>&1 || true

title "Incident 1: checkout is slow"
apply "$(dirname "$0")/pod.yaml"
wait_ready checkout-api

note ""
note "Measuring the pod's average CPU for 10 seconds, the way a dashboard would..."
u0=$(cg_key checkout-api cpu.stat usage_usec); sleep 10; u1=$(cg_key checkout-api cpu.stat usage_usec)
echo "  average CPU: $(( (u1 - u0) / 10 / 1000 ))m   (limit: 200m)"
step "kubectl -n $NS logs checkout-api --tail=3"
kubectl -n "$NS" logs checkout-api --tail=3 | sed 's/^/  /'

cat <<'MSG'

  THE TICKET
  "Checkout takes almost a second. The target is under 100 ms.
   The CPU graph shows the pod well under its limit, so it can't be CPU. Right?"

  YOUR JOB: find out why each request is so slow.

  Things to try:
    kubectl -n lab logs -f checkout-api
    ./scripts/watch.sh checkout-api
    kubectl -n lab exec checkout-api -- cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/cpu.stat

  When you know:  make answer-1 CAUSE=<one or two words>
  Stuck?          make hint-1
MSG
