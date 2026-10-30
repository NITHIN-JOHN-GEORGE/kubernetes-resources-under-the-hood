#!/usr/bin/env bash
# Module 15: LimitRange fills in missing requests/limits and rejects values outside a range.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
LNS=lab-limits
pod=lr-defaults

module_cleanup() {
  [ "${KEEP:-0}" = "1" ] && return 0
  kubectl delete ns "$LNS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
cleanup_on_exit module=15
title "Module 15: LimitRange"
if kubectl get ns "$LNS" >/dev/null 2>&1; then
  note "Removing the namespace left over from an earlier run..."
  kubectl delete ns "$LNS" --wait=true >/dev/null
fi

run kubectl apply -f "$dir/limitrange.yaml"
step "kubectl -n $LNS describe limitrange container-defaults"
kubectl -n "$LNS" describe limitrange container-defaults | sed 's/^/  /'

note "pod-no-resources.yaml has no resources section at all."
run kubectl apply -f "$dir/pod-no-resources.yaml"
kubectl -n "$LNS" wait --for=condition=Ready "pod/$pod" --timeout="$WAIT" >/dev/null

step "kubectl -n $LNS get pod $pod -o jsonpath='{.spec.containers[0].resources}'"
res="$(kubectl -n "$LNS" get pod "$pod" -o jsonpath='{.spec.containers[0].resources}')"
echo "  $res"
step "kubectl -n $LNS get pod $pod -o jsonpath='{.metadata.annotations}'"
echo "  $(kubectl -n "$LNS" get pod "$pod" -o jsonpath='{.metadata.annotations}')"
note "The LimitRanger admission plugin wrote the defaults into the pod spec and left an annotation saying so."

lcg() { kubectl -n "$LNS" exec "$pod" -c main -- cat "/sys/fs/cgroup/$1"; }
step "kubectl -n $LNS exec $pod -- cat /sys/fs/cgroup/{cpu.max,memory.max}"
cpumax="$(lcg cpu.max)"; memmax="$(lcg memory.max)"
printf '  cpu.max     %s\n  memory.max  %s\n' "$cpumax" "$memmax"
note "Injected values are ordinary values: they end up in the cgroup exactly like hand-written ones."

step "kubectl apply -f pod-too-big.yaml   (memory limit 512Mi)"
out_big="$(kubectl apply -f "$dir/pod-too-big.yaml" 2>&1 || true)"
echo "  $out_big"

title "Checks"
case "$res" in *'"memory":"128Mi"'*) pass "default memory limit 128Mi was injected";; *) fail "no default memory limit in the pod spec";; esac
case "$res" in *'"cpu":"100m"'*) pass "default CPU request 100m was injected";; *) fail "no default CPU request in the pod spec";; esac
[ "$memmax" = "134217728" ] && pass "memory.max is 134217728 (128Mi)" || fail "memory.max is $memmax"
[ "${cpumax%% *}" = "20000" ] && pass "cpu.max quota is 20000 (200m)" || fail "cpu.max is $cpumax"
case "$out_big" in *"maximum memory usage per Container is 256Mi"*) pass "pod over the max was rejected";; *) fail "pod over the max was not rejected";; esac

finish
