#!/usr/bin/env bash
# Incident 4: the controller is slow and waits for CPU, but it's never throttled.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found --wait=true >/dev/null 2>&1
title "Incident 4: waiting, but never throttled"

stage "1. The scene"
apply "$(dirname "$0")/pods.yaml"
wait_ready controller
for p in batch-1 batch-2 batch-3; do wait_ready "$p"; done
cat <<'MSG'

  controller handles one request a second. Each request splits its work across
  4 worker processes that run at the same time, about 40 ms of CPU each.
  Its CPU limit is 2 cores: far more than one request ever needs.

  It shares the worker node with three batch jobs that run all the time.
MSG
pause

stage "2. What the on-call engineer sees"
note "  The app's own log of how long each request took:"
sleep 5
run kubectl -n "$NS" logs controller --tail=3
echo
note "  And the throttling graph for controller, over 10 seconds:"
p0=$(cg_key controller cpu.stat nr_periods); t0=$(cg_key controller cpu.stat nr_throttled); sleep 10
p1=$(cg_key controller cpu.stat nr_periods); t1=$(cg_key controller cpu.stat nr_throttled)
echo "  throttled in $(( t1 - t0 )) of $(( p1 - p0 )) periods   → not throttled"
pause

stage "3. The ticket"
cat <<'MSG'
  "The controller is slow and its 'CPU wait' is high, but it's never throttled.
   Its limit is way above what it uses. Is the node broken?"

  YOUR TURN. Find out what the controller is waiting for. Look at these, in order:

    1. Is the controller's own limit stopping it? Read it twice, a few seconds apart.
         kubectl exec controller -- cat /sys/fs/cgroup/cpu.stat

    2. How much of the time its threads were ready to run, but waiting.
         kubectl exec controller -- cat /sys/fs/cgroup/cpu.pressure

    3. The same, for the whole node.
         docker exec under-the-hood-worker cat /proc/pressure/cpu

    4. Who it shares the node with, and what they asked for.
         kubectl get pods -l incident -o custom-columns=NAME:.metadata.name,REQUEST:.spec.containers[0].resources.requests.cpu,LIMIT:.spec.containers[0].resources.limits.cpu
         kubectl get node under-the-hood-worker -o jsonpath='{.status.capacity.cpu}{" CPUs\n"}'

  A clue, one at a time:   make hint-4
  When you know:           make answer-4 CAUSE=<one or two words>
MSG
