#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
kubectl get ns lab-quota >/dev/null 2>&1 || { fail "namespace lab-quota not found. Run the README's first step."; finish; }
kubectl -n lab-quota get pod q-no-requests >/dev/null 2>&1 && fail "q-no-requests exists, but the quota should refuse it" || pass "q-no-requests was refused (must specify requests)"
kubectl -n lab-quota get pod q-small >/dev/null 2>&1 && pass "q-small fit inside the quota" || fail "q-small should have been created"
kubectl -n lab-quota get pod q-big >/dev/null 2>&1 && fail "q-big exists, but it would exceed the quota" || pass "q-big was refused (exceeded quota)"
finish
