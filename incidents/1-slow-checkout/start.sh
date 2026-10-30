#!/usr/bin/env bash
# Incident 1: checkout is slow, but the CPU graph looks fine.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found --wait=true >/dev/null 2>&1
title "Incident 1: checkout is slow"

stage "1. The scene"
apply "$(dirname "$0")/pod.yaml"
wait_ready checkout-api
cat <<'MSG'

  checkout-api handles one request a second. Each request splits its work across
  4 worker processes that run at the same time, about 40 ms of CPU each.
  Its CPU limit is 200m.
MSG
pause

stage "2. What the on-call engineer sees"
note "  The CPU graph: the pod's average CPU over 10 seconds, like a dashboard..."
m=$(pod_millicores checkout-api 10)
echo "  average CPU: ${m}m   (limit: 200m)   → looks fine"
echo
note "  The app's own log of how long each request took:"
run kubectl -n "$NS" logs checkout-api --tail=3
pause

stage "3. The ticket"
cat <<'MSG'
  "Checkout takes almost a second. The target is under 100 ms.
   The CPU graph shows the pod under its limit, so it can't be CPU. Right?"

  YOUR TURN. Find out why each request is so slow. Look at these, in order:

    1. How the limit is written in the kernel. What does each number mean?
         kubectl exec checkout-api -- cat /sys/fs/cgroup/cpu.max

    2. Whether the kernel ever made the pod wait. Read it twice, a few seconds apart.
         kubectl exec checkout-api -- cat /sys/fs/cgroup/cpu.stat

    3. Watch it live (Ctrl-C to stop). Compare "used" with "throttled".
         ./scripts/watch.sh checkout-api

  A clue, one at a time:   make hint-1
  When you know:           make answer-1 CAUSE=<one or two words>
MSG
