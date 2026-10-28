#!/usr/bin/env bash
# Module 08: a higher-priority pod that doesn't fit evicts (preempts) a lower-priority one.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"

module_cleanup() {
  [ "${KEEP:-0}" = "1" ] && return 0
  kubectl delete priorityclass lab-low lab-high --ignore-not-found >/dev/null 2>&1 || true
}
cleanup_on_exit module=08
title "Module 08: priority classes and preemption"
kubectl -n "$NS" delete pod -l module=08 --ignore-not-found >/dev/null 2>&1 || true
wait_lab_empty

run kubectl apply -f "$dir/priorityclasses.yaml"
step "kubectl get priorityclass"
kubectl get priorityclass | sed 's/^/  /'
note "system-node-critical and system-cluster-critical are built in. Higher value = more important."

alloc="$(worker_cpu_allocatable)"; used="$(worker_cpu_requested)"; free=$(( alloc - used ))
want=$(( free - 100 ))
step "CPU on $WORKER (millicores)"
printf '  allocatable %sm   already requested %sm   free %sm\n' "$alloc" "$used" "$free"
if [ "$want" -lt 200 ]; then
  fail "not enough free CPU on the worker (${free}m); delete other pods and retry"; finish
fi
note "Each pod will request ${want}m, so the worker can hold one of them but not both."

ensure_ns
step "sed s/__CPU__/${want}m/ pod-low.yaml | kubectl -n $NS apply -f -"
sed "s/__CPU__/${want}m/" "$dir/pod-low.yaml" | kubectl -n "$NS" apply -f -
wait_ready prio-low

step "sed s/__CPU__/${want}m/ pod-high.yaml | kubectl -n $NS apply -f -"
sed "s/__CPU__/${want}m/" "$dir/pod-high.yaml" | kubectl -n "$NS" apply -f -
note "prio-high can't fit, so the scheduler looks for lower-priority pods to remove."

ok_high=0
if kubectl -n "$NS" wait --for=condition=Ready pod/prio-high --timeout="$WAIT" >/dev/null 2>&1; then ok_high=1; fi

step "kubectl -n $NS get events --field-selector involvedObject.name=prio-low"
kubectl -n "$NS" get events --field-selector involvedObject.name=prio-low \
  -o custom-columns=REASON:.reason,MESSAGE:.message --sort-by=.lastTimestamp | sed 's/^/  /'
step "kubectl -n $NS get pods -l module=08 -o custom-columns=..."
kubectl -n "$NS" get pods -l module=08 \
  -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority,STATUS:.status.phase,NODE:.spec.nodeName 2>/dev/null | sed 's/^/  /'
note "The admission controller copied each class's value into .spec.priority when the pod was created."
note "prio-low shows Failed: the scheduler marked it with a DisruptionTarget condition and deleted it gracefully."

title "Checks"
[ "$ok_high" = "1" ] && pass "prio-high is Running on the worker" || fail "prio-high did not become Ready"
if kubectl -n "$NS" get events --field-selector involvedObject.name=prio-low,reason=Preempted -o name | grep -q .; then
  pass "prio-low has a Preempted event"
else
  fail "no Preempted event for prio-low"
fi
[ "$(kubectl -n "$NS" get pod prio-high -o jsonpath='{.spec.priority}')" = "1000000" ] && pass "prio-high has .spec.priority 1000000" || fail "unexpected priority on prio-high"

finish
