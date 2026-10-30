#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
[ "$(kubectl get node "$WORKER" -o jsonpath='{.metadata.labels.lab-profile}')" = pids ] && pass "the cluster uses the pids profile" || { fail "this lab needs: make clean && make cluster PROFILE=pids"; finish; }
need_pod pid-hog labs/20-pids-and-disk/pod-pids.yaml
[ "$(on_node "cat $(pod_cgroup_dir pid-hog)/pids.max")" = 64 ] && pass "the pod's pids.max is 64" || fail "pids.max should be 64"
[ "$(kubectl -n "$NS" get pod pid-hog -o jsonpath='{.status.phase}')" = Running ] && pass "pid-hog is still Running: forks are refused, nothing is killed" || fail "pid-hog should still be running"
if kubectl -n "$NS" get pod disk-hog >/dev/null 2>&1; then
  [ "$(kubectl -n "$NS" get pod disk-hog -o jsonpath='{.status.reason}')" = Evicted ] && pass "disk-hog was evicted for its disk use" || fail "disk-hog hasn't been evicted yet (give it a minute)"
else fail "pod disk-hog not found (second step)"; fi
finish
