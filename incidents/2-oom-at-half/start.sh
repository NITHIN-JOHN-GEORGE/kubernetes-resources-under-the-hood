#!/usr/bin/env bash
# Incident 2: a pod keeps restarting, but its memory graph sits at about half the limit.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found >/dev/null 2>&1 || true

title "Incident 2: OOMKilled at 50%"
apply "$(dirname "$0")/pod.yaml"
wait_ready report-worker
pdir="$(pod_cgroup_dir report-worker)"

note ""
note "Sampling memory every 15 seconds, the way a dashboard scraping metrics would..."
for i in 1 2 3 4; do
  cur=$(on_node "cat $pdir/memory.current"); inact=$(on_node "awk '\$1==\"inactive_file\"{print \$2}' $pdir/memory.stat")
  ws=$(( (cur - inact) / 1048576 ))
  restarts=$(kubectl -n "$NS" get pod report-worker -o jsonpath='{.status.containerStatuses[0].restartCount}')
  echo "  sample $i: working set ${ws} MiB of 256 MiB ($(( ws * 100 / 256 ))%)   restarts: $restarts"
  [ "$i" -lt 4 ] && sleep 15
done

cat <<'MSG'

  THE TICKET
  "report-worker keeps restarting with OOMKilled. But the dashboard never shows it
   above about half its memory limit. Is the OOM killer broken?"

  YOUR JOB: find out what is using the memory when it gets killed.

  Things to try:
    kubectl -n lab get pod report-worker
    kubectl -n lab logs report-worker --previous
    ./scripts/watch.sh report-worker
    POD_DIR=$(./scripts/pod-cgroup.sh report-worker)
    docker exec under-the-hood-worker cat $POD_DIR/memory.events $POD_DIR/memory.peak

  When you know:  make answer-2 CAUSE=<one or two words>
  Stuck?          make hint-2
MSG
