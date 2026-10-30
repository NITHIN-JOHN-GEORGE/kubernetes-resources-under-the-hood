#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
[ "$(kubectl get node "$WORKER" -o jsonpath='{.metadata.labels.lab-profile}')" = pressure ] && pass "the cluster uses the pressure profile" || { fail "this lab needs: make clean && make cluster PROFILE=pressure"; finish; }
need_pod memory-hog labs/18-node-pressure-eviction/
[ "$(kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.reason}')" = Evicted ] && pass "memory-hog was Evicted" || fail "memory-hog hasn't been evicted yet (give it a minute)"
kubectl -n "$NS" get pod memory-hog -o jsonpath='{.status.message}' | grep -q "low on resource: memory" && pass "because the node was low on memory" || fail "the eviction message should mention memory"
for p in calm-burstable calm-guaranteed; do
  [ "$(kubectl -n "$NS" get pod $p -o jsonpath='{.status.phase}')" = Running ] && pass "$p kept running" || fail "$p should still be running"
done
finish
