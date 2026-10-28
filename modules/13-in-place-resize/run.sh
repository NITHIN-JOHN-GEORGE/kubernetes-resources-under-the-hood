#!/usr/bin/env bash
# Module 13: change a running pod's CPU and memory without restarting it, and watch the cgroup follow.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=resize-demo

cleanup_on_exit module=13
title "Module 13: in-place pod resize"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true

minor="$(server_minor)"
if [ "${minor:-0}" -lt 33 ]; then
  note "SKIP: in-place resize is on by default from Kubernetes 1.33; this cluster is 1.${minor}."
  exit 0
fi

apply "$dir/pod.yaml"
wait_ready "$pod"
pdir="$(pod_cgroup_dir "$pod")"

show() {
  printf '  container  cpu.max %-14s memory.max %-10s cpu.weight %s\n' "$(cg "$pod" cpu.max)" "$(cg "$pod" memory.max)" "$(cg "$pod" cpu.weight)"
  printf '  pod        cpu.max %-14s memory.max %s\n' "$(on_node "cat $pdir/cpu.max")" "$(on_node "cat $pdir/memory.max")"
}
step "cgroup files before (200m / 64Mi)"
show
c0="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].containerID}')"

patch='{"spec":{"containers":[{"name":"main","resources":{"requests":{"cpu":"500m","memory":"128Mi"},"limits":{"cpu":"500m","memory":"128Mi"}}}]}}'
step "kubectl -n $NS patch pod $pod --subresource resize --patch '$patch'"
if ! kubectl -n "$NS" patch pod "$pod" --subresource resize --patch "$patch" | sed 's/^/  /'; then
  fail "resize patch failed. kubectl 1.32 or newer is needed for --subresource resize"; finish
fi

cpumax=""
for _ in $(seq 1 30); do
  cpumax="$(cg "$pod" cpu.max)"
  [ "${cpumax%% *}" = "50000" ] && break
  sleep 2
done
step "cgroup files after (500m / 128Mi)"
show
note "The kubelet asked the runtime to update the running container's cgroup. The processes never stopped."

step "kubectl -n $NS get pod $pod -o jsonpath=... (spec vs status)"
printf '  spec    limits %s\n' "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.spec.containers[0].resources.limits}')"
printf '  status  limits %s\n' "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].resources.limits}')"
printf '  restartCount %s\n' "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
note "spec is what you asked for; status is what the kubelet has actually applied."

title "Checks"
[ "${cpumax%% *}" = "50000" ] && pass "container cpu.max went from 20000 to 50000" || fail "container cpu.max is $cpumax"
[ "$(cg "$pod" memory.max)" = "134217728" ] && pass "container memory.max is 134217728 (128Mi)" || fail "container memory.max is $(cg "$pod" memory.max)"
[ "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')" = "0" ] && pass "restartCount is still 0" || fail "the container restarted"
[ "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].containerID}')" = "$c0" ] && pass "same container ID as before the resize" || fail "container ID changed"
[ "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].resources.limits.cpu}')" = "500m" ] && pass "status reports the new 500m CPU limit" || fail "status does not show 500m yet"
[ "$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.qosClass}')" = "Guaranteed" ] && pass "QoS class is still Guaranteed" || fail "QoS class changed"

finish
