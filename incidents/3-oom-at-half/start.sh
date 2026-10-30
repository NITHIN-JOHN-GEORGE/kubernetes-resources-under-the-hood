#!/usr/bin/env bash
# Incident 3: a pod keeps restarting, but its memory graph sits at about half the limit.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found --wait=true >/dev/null 2>&1
title "Incident 3: OOMKilled at 50%"

stage "1. The scene"
apply "$(dirname "$0")/pod.yaml"
wait_ready report-worker
cat <<'MSG'

  report-worker keeps a cache in memory and builds a report every 20 seconds.
  Its memory limit is 256Mi.
MSG
pause

stage "2. What the on-call engineer sees"
note "  The memory graph: the working set, sampled every 15 seconds like a metrics scraper..."
pdir="$(pod_cgroup_dir report-worker)"
for i in 1 2 3 4; do
  cur=$(on_node "cat $pdir/memory.current"); inact=$(on_node "awk '\$1==\"inactive_file\"{print \$2}' $pdir/memory.stat")
  ws=$(( (cur - inact) / 1048576 ))
  restarts=$(kubectl -n "$NS" get pod report-worker -o jsonpath='{.status.containerStatuses[0].restartCount}')
  echo "  sample $i: working set ${ws} MiB of 256 MiB ($(( ws * 100 / 256 ))%)   restarts so far: $restarts"
  [ "$i" -lt 4 ] && sleep 15
done
echo
note "  Never above about 40%, yet it keeps restarting."
pause

stage "3. The ticket"
cat <<'MSG'
  "report-worker keeps restarting with OOMKilled. But the dashboard never shows it
   above about half its memory limit. Is the OOM killer broken?"

  YOUR TURN. Find out what uses the memory when it dies. Look at these, in order:

    1. How it died. Look at "Last State" and its reason and exit code.
         kubectl describe pod report-worker | grep -A4 "Last State"

    2. What it was doing just before. Find the line printed right before each restart.
         kubectl logs report-worker

    3. What the kernel remembers. Compare memory.peak with memory.max (256Mi = 268435456).
         POD_DIR=$(./scripts/pod-cgroup.sh report-worker)
         docker exec under-the-hood-worker cat $POD_DIR/memory.peak $POD_DIR/memory.events

  A clue, one at a time:   make hint-3
  When you know:           make answer-3 CAUSE=<one or two words>
MSG
