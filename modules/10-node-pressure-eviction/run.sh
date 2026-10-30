#!/usr/bin/env bash
# Module 10: when the node runs low on memory, the kubelet evicts pods before the kernel OOM killer acts.
# This module changes the worker's kubelet config and always restores it on exit.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
MARGIN_MI="${MARGIN_MI:-600}"

module_cleanup() {
  kubelet_restore
  # Wait for the memory-pressure taint to clear so later modules can schedule.
  for _ in $(seq 1 30); do
    kubectl get node "$WORKER" -o jsonpath='{.spec.taints[*].key}' | grep -q memory-pressure || return 0
    sleep 2
  done
}
cleanup_on_exit module=10
title "Module 10: node-pressure eviction"
kubectl -n "$NS" delete pod -l module=10 --ignore-not-found >/dev/null 2>&1 || true

# How the kubelet computes memory.available: node capacity minus the working set of the node's
# root cgroup (memory.current minus inactive_file). We compute the same number on the node.
avail_mi="$(on_node '
  total_kb=$(awk "/^MemTotal:/ {print \$2}" /proc/meminfo)
  if [ -f /sys/fs/cgroup/memory.current ]; then
    cur=$(cat /sys/fs/cgroup/memory.current)
    inact=$(awk "\$1==\"inactive_file\" {print \$2}" /sys/fs/cgroup/memory.stat)
    echo $(( (total_kb * 1024 - (cur - inact)) / 1048576 ))
  else
    echo $(( $(awk "/^MemAvailable:/ {print \$2}" /proc/meminfo) / 1024 ))
  fi')"
threshold_mi=$(( avail_mi - MARGIN_MI ))
step "memory.available on $WORKER"
echo "  ${avail_mi}Mi  (MemTotal minus the node cgroup's working set)"
if [ "$threshold_mi" -lt 200 ]; then
  fail "only ${avail_mi}Mi available; give Docker more memory and try again"; finish
fi

step "Set evictionHard memory.available=${threshold_mi}Mi on $WORKER and restart the kubelet"
note "That leaves about ${MARGIN_MI}Mi of headroom before the node counts as under memory pressure."
kubelet_backup
kubelet_set_eviction_hard "memory.available=${threshold_mi}Mi" "nodefs.available=0%" "nodefs.inodesFree=0%" "imagefs.available=0%"
kubelet_set evictionPressureTransitionPeriod 10s
kubelet_restart
printf '  %s\n' "$(kubelet_live evictionHard)"

apply "$dir/pods.yaml"
wait_ready calm-burstable
wait_ready calm-guaranteed
note "memory-hog (BestEffort) now allocates 10 MiB every 0.2s, up to 1000 MiB."

reason=""
for _ in $(seq 1 90); do
  reason="$(kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.reason}' 2>/dev/null || true)"
  [ "$reason" = "Evicted" ] && break
  sleep 2
done

step "kubectl get node $WORKER -o jsonpath='{.status.conditions[?(@.type==\"MemoryPressure\")]}'"
kubectl get node "$WORKER" -o jsonpath='{range .status.conditions[?(@.type=="MemoryPressure")]}  status={.status}  reason={.reason}{"\n"}{end}'
step "kubectl get node $WORKER -o jsonpath='{.spec.taints}'"
echo "  $(kubectl get node "$WORKER" -o jsonpath='{.spec.taints}')"
note "The control plane adds a node.kubernetes.io/memory-pressure:NoSchedule taint a few seconds after the"
note "condition turns True, so it may not show up yet. The kubelet also refuses new BestEffort pods meanwhile."

step "kubectl -n $NS get pods -l module=10"
kubectl -n "$NS" get pods -l module=10 | sed 's/^/  /'
step "kubectl -n $NS get pod memory-hog -o jsonpath='{.status.message}'"
echo "  $(kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.message}')"
note "The kubelet ranks pods by (1) usage above requests, (2) priority, (3) usage. The hog has no requests"
note "and the most usage, so it goes first. The calm pods use less than they requested and are left alone."

title "Checks"
[ "$reason" = "Evicted" ] && pass "memory-hog was Evicted" || fail "memory-hog was not evicted (reason='${reason:-none}'). Try MARGIN_MI=400"
case "$(kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.message}')" in
  *"low on resource: memory"*) pass "eviction message says the node was low on memory";;
  *) fail "eviction message does not mention memory";;
esac
for p in calm-burstable calm-guaranteed; do
  ph="$(kubectl -n "$NS" get pod "$p" -o jsonpath='{.status.phase}')"
  [ "$ph" = "Running" ] && pass "$p is still Running" || fail "$p is $ph"
done

finish
