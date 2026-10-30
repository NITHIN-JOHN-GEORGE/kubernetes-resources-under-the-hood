#!/usr/bin/env bash
# Check an answer for incident 2 and explain what was going on.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *spike*|*peak*|*burst*|*report*|*short*) pass "Correct: a short memory spike, between dashboard samples." ;;
  "") echo "Usage: make answer-2 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-2"; exit 1 ;;
esac

title "What was happening"
pdir="$(pod_cgroup_dir report-worker)"
step "docker exec under-the-hood-worker cat <pod cgroup>/memory.peak <pod cgroup>/memory.events"
echo "  memory.peak: $(( $(on_node "cat $pdir/memory.peak 2>/dev/null || echo 0") / 1048576 )) MiB   (memory.max: 256 MiB)"
on_node "grep -E '^(max|oom_kill) ' $pdir/memory.events" | sed 's/^/  /'
step "kubectl -n $NS logs report-worker --previous --tail=2"
kubectl -n "$NS" logs report-worker --previous --tail=2 2>/dev/null | sed 's/^/  /'
cat <<'MSG'

  The worker holds a 100 MiB cache all the time: that's the "about 50%" the dashboard sees.
  Every 20 seconds it builds a report that needs another 200 MiB for well under a second.
  100 + 200 MiB is more than the 256 MiB limit, so the kernel OOM-kills it mid-report.
  The spike lasts a fraction of a second, so a dashboard sampling every 15 seconds almost
  never catches it. memory.peak and memory.events do: the kernel doesn't sample, it counts.

  The fix: size the limit for the peak, not the average (here, 320Mi or more), or change the
  code so the report doesn't need to be built in memory all at once.
  Clean up with: make incident-clean
MSG
