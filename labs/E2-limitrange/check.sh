#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
NS=lab-limits
need_pod lr-defaults labs/E2-limitrange/pod-no-resources.yaml
[ "$(cg lr-defaults cpu.max)" = "20000 100000" ] && pass "the injected 200m default became cpu.max 20000 100000" || fail "cpu.max should be 20000 100000"
[ "$(cg lr-defaults memory.max)" = 134217728 ] && pass "the injected 128Mi default became memory.max 134217728" || fail "memory.max should be 134217728"
kubectl -n lab-limits get pod lr-too-big >/dev/null 2>&1 && fail "the too-big pod exists, but the LimitRange should refuse it" || pass "the pod over the maximum was refused"
finish
