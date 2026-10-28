#!/usr/bin/env bash
# Module 09: ResourceQuota caps what a whole namespace can request. The API server enforces it at create time.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
QNS=lab-quota

module_cleanup() {
  [ "${KEEP:-0}" = "1" ] && return 0
  kubectl delete ns "$QNS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
cleanup_on_exit module=09
title "Module 09: ResourceQuota"
if kubectl get ns "$QNS" >/dev/null 2>&1; then
  note "Removing the namespace left over from an earlier run..."
  kubectl delete ns "$QNS" --wait=true >/dev/null
fi

run kubectl apply -f "$dir/quota.yaml"
# The quota controller fills in .status before the API server will admit pods against it.
for _ in $(seq 1 30); do
  [ -n "$(kubectl -n "$QNS" get quota compute -o jsonpath='{.status.hard.pods}' 2>/dev/null)" ] && break
  sleep 1
done
step "kubectl -n $QNS describe quota compute"
kubectl -n "$QNS" describe quota compute | sed 's/^/  /'

# Try to create a pod and capture what the API server says.
try() { kubectl apply -f "$1" 2>&1 || true; }

step "kubectl apply -f pod-no-requests.yaml"
out_none="$(try "$dir/pod-no-requests.yaml")"; echo "  $out_none"
note "With a quota on requests.cpu and requests.memory, every pod in the namespace must set them."

step "kubectl apply -f pod-small.yaml   (200m / 100Mi)"
out_small="$(try "$dir/pod-small.yaml")"; echo "  $out_small"

step "kubectl apply -f pod-big.yaml     (400m / 100Mi)"
out_big="$(try "$dir/pod-big.yaml")"; echo "  $out_big"
note "200m is already used, so 400m more would be 600m against a 500m limit."

sleep 2
step "kubectl -n $QNS describe quota compute"
kubectl -n "$QNS" describe quota compute | sed 's/^/  /'
note "Used is the sum of requests of pods in the namespace, kept up to date by the quota controller."

title "Checks"
case "$out_none" in *"must specify"*) pass "pod without requests was rejected";; *) fail "pod without requests was not rejected";; esac
case "$out_small" in *created*|*unchanged*|*configured*) pass "pod within quota was admitted";; *) fail "pod within quota was rejected";; esac
case "$out_big" in *"exceeded quota"*) pass "pod over quota was rejected with 'exceeded quota'";; *) fail "pod over quota was not rejected";; esac
used="$(kubectl -n "$QNS" get quota compute -o jsonpath='{.status.used.requests\.cpu}')"
[ "$used" = "200m" ] && pass "quota shows requests.cpu used = 200m" || fail "quota shows requests.cpu used = '$used'"

finish
