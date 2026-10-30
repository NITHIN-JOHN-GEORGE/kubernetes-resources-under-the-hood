#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
kubectl get ns lab-checkpoints >/dev/null 2>&1 && pass "namespace lab-checkpoints has its quota" || fail "namespace lab-checkpoints not found (first step)"
kubectl -n lab-checkpoints get pod over-quota >/dev/null 2>&1 && fail "over-quota exists, but the quota should have refused it" || pass "over-quota was refused by the API server (it doesn't exist)"
if kubectl -n "$NS" get pod too-big >/dev/null 2>&1; then
  [ "$(kubectl -n "$NS" get pod too-big -o jsonpath='{.status.phase}')" = Pending ] && pass "too-big is Pending: the scheduler found no room" || fail "too-big should be Pending"
else fail "pod too-big not found (second step)"; fi
need_pod pod-ok labs/09-four-checkpoints/pod-ok.yaml
[ "$(cg pod-ok cpu.max)" = "50000 100000" ] && pass "pod-ok reached the kernel: cpu.max is 50000 100000" || fail "pod-ok's cpu.max should be 50000 100000"
finish
