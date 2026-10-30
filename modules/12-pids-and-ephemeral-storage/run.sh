#!/usr/bin/env bash
# Module 12: two limits people forget. Process IDs (a cgroup) and local disk (the kubelet).
# The PID part changes the worker's kubelet config and restores it straight after.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
PIDS=64

module_cleanup() { kubelet_restore; }
cleanup_on_exit module=12
title "Module 12: PIDs and ephemeral storage"
kubectl -n "$NS" delete pod -l module=12 --ignore-not-found >/dev/null 2>&1 || true

# ---------------------------------------------------------------- PIDs
step "Set podPidsLimit=$PIDS on $WORKER and restart the kubelet"
kubelet_backup
kubelet_set podPidsLimit "$PIDS"
kubelet_restart
echo "  $(kubelet_live podPidsLimit)"
note "The kubelet writes this into pids.max of every new pod's cgroup."

apply "$dir/pod-pids.yaml"
wait_ready pid-hog
pdir="$(pod_cgroup_dir pid-hog)"

note "pid-hog tries to start 100 background processes as soon as it starts."
out=""
for _ in $(seq 1 30); do
  out="$(kubectl -n "$NS" logs pid-hog 2>/dev/null || true)"
  case "$out" in *"spawner finished"*) break;; esac
  sleep 1
done
step "kubectl -n $NS logs pid-hog | tail -4"
echo "$out" | tail -n 4 | sed 's/^/  /'
note "fork() fails with EAGAIN once the pod holds $PIDS processes, so the loop stops short of 100."

step "docker exec $WORKER cat <pod cgroup>/{pids.max,pids.current,pids.events}"
pmax="$(on_node "cat $pdir/pids.max")"; pcur="$(on_node "cat $pdir/pids.current")"
# Older kernels count the refusal in the forking container's pids.events, newer ones also in the
# pod's (where the limit is). Add up the pod and its containers so both cases work.
pev="$(on_node "cat $pdir/pids.events $pdir/*/pids.events 2>/dev/null; true" | awk '$1=="max" {s+=$2} END {print s+0}')"
printf '  pids.max      %s\n  pids.current  %s\n  pids.events   max %s  (pod + containers)\n' "$pmax" "$pcur" "$pev"
note "pids.events 'max' counts the forks refused because of the limit."
note "Without a limit, one fork bomb in one pod could use up every PID on the node and break the node itself."

kubelet_restore

# ------------------------------------------------------- Ephemeral storage
apply "$dir/pod-disk.yaml"
note "disk-hog writes 100 MiB to an emptyDir with an ephemeral-storage limit of 50Mi."
note "Waiting for the kubelet to notice (it measures disk usage periodically, so this can take a minute)..."
reason=""
for _ in $(seq 1 75); do
  reason="$(kubectl -n "$NS" get pod disk-hog -o jsonpath='{.status.reason}' 2>/dev/null || true)"
  [ "$reason" = "Evicted" ] && break
  sleep 2
done
step "kubectl -n $NS get pod disk-hog -o jsonpath='{.status.reason}: {.status.message}'"
dmsg="$(kubectl -n "$NS" get pod disk-hog -o jsonpath='{.status.message}')"
echo "  ${reason:-<none>}: $dmsg"
note "There is no cgroup for disk space. The kubelet adds up the container's writable layer, its logs"
note "and its emptyDir volumes, and evicts the pod when the total crosses the limit."

title "Checks"
[ "$pmax" = "$PIDS" ] && pass "pod pids.max is $PIDS" || fail "pod pids.max is $pmax"
[ "${pcur:-0}" -le "$PIDS" ] && pass "pids.current ($pcur) never went past the limit" || fail "pids.current is $pcur"
[ "${pev:-0}" -ge 1 ] && pass "pids.events recorded $pev refused fork(s)" || fail "pids.events shows no refused forks"
case "$out" in *"started all 100"*) fail "all 100 processes started";; *) pass "the shell could not start all 100 processes";; esac
[ "$reason" = "Evicted" ] && pass "disk-hog was Evicted" || fail "disk-hog was not evicted (reason='${reason:-none}')"
case "$dmsg" in *"ephemeral"*|*"EmptyDir"*) pass "eviction message is about ephemeral storage";; *) fail "eviction message doesn't mention ephemeral storage";; esac

finish
