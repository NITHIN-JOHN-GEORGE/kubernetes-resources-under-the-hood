#!/usr/bin/env bash
# Module 06: capacity minus reservations is what the scheduler can hand out.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=too-big

cleanup_on_exit module=06
title "Module 06: node allocatable and reservations"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true

step "kubectl get node $WORKER -o jsonpath=... (capacity vs allocatable)"
printf '  %-18s %-14s %s\n' "resource" "capacity" "allocatable"
for r in cpu memory pods ephemeral-storage; do
  printf '  %-18s %-14s %s\n' "$r" \
    "$(kubectl get node "$WORKER" -o jsonpath="{.status.capacity['$r']}")" \
    "$(kubectl get node "$WORKER" -o jsonpath="{.status.allocatable['$r']}")"
done
note "allocatable = capacity - systemReserved - kubeReserved - evictionHard threshold."

step "kubectl get --raw /api/v1/nodes/$WORKER/proxy/configz (reservation settings)"
for k in systemReserved kubeReserved evictionHard enforceNodeAllocatable; do
  printf '  %-24s %s\n' "$k" "$(kubelet_live "$k" | sed "s/^\"$k\"://" || true)"
done
note "An empty value means the setting isn't configured. kind reserves nothing, so allocatable is close to capacity."
note "kind sets the disk eviction thresholds to 0% so a laptop's full disk doesn't evict everything."

root="$(kubepods_root)"
step "docker exec $WORKER cat $root/memory.max"
podmax="$(on_node "cat $root/memory.max")"
echo "  $podmax"
note "This is the ceiling on all pods together. The kubelet sets it to capacity - systemReserved - kubeReserved."
note "The eviction threshold is NOT subtracted here: that part is enforced by the kubelet evicting pods (module 07)."

cap_ki="$(kubectl get node "$WORKER" -o jsonpath='{.status.capacity.memory}' | sed 's/Ki$//')"
alloc_ki="$(kubectl get node "$WORKER" -o jsonpath='{.status.allocatable.memory}' | sed 's/Ki$//')"
want_mi=$(( alloc_ki / 1024 + 1024 ))

ensure_ns
step "sed s/__MEM__/${want_mi}Mi/ pod.yaml | kubectl -n $NS apply -f -"
sed "s/__MEM__/${want_mi}Mi/" "$dir/pod.yaml" | kubectl -n "$NS" apply -f -
note "The pod asks for ${want_mi}Mi, 1Gi more than the worker's allocatable memory."

msg=""
for _ in $(seq 1 30); do
  msg="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}')"
  [ -n "$msg" ] && break
  sleep 1
done
step "kubectl -n $NS get pod $pod"
kubectl -n "$NS" get pod "$pod" | sed 's/^/  /'
step "kubectl -n $NS get pod $pod -o jsonpath='{.status.conditions[?(@.type==\"PodScheduled\")].message}'"
echo "  $msg"
note "The scheduler only compares requests with allocatable. It never looks at real usage."

title "Checks"
[ "$alloc_ki" -le "$cap_ki" ] && pass "allocatable memory (${alloc_ki}Ki) <= capacity (${cap_ki}Ki)" || fail "allocatable is larger than capacity"
if [ "$podmax" = "max" ] || [ "$podmax" -ge $(( alloc_ki * 1024 )) ]; then
  pass "pod tree memory.max ($podmax) is at least allocatable"
else
  fail "pod tree memory.max ($podmax) is below allocatable"
fi
phase="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.phase}')"
[ "$phase" = "Pending" ] && pass "$pod is Pending" || fail "$pod is $phase"
case "$msg" in *"Insufficient memory"*) pass "scheduler reports Insufficient memory";; *) fail "no 'Insufficient memory' in the scheduling message";; esac

finish
