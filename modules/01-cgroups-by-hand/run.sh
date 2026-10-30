#!/usr/bin/env bash
# Module 01: build two cgroups by hand on the node, with no Kubernetes involved.
# Everything here is plain Linux: mkdir, echo and cat under /sys/fs/cgroup.
source "$(dirname "$0")/../../lib/common.sh"
CG=/sys/fs/cgroup/lab-cpu
MG=/sys/fs/cgroup/lab-mem
node() { docker exec "$WORKER" sh -c "$1"; }

module_cleanup() {
  node "for g in $CG $MG; do [ -d \$g ] || continue; for p in \$(cat \$g/cgroup.procs 2>/dev/null); do kill -9 \$p 2>/dev/null; done; done; sleep 1; rmdir $CG $MG 2>/dev/null; true"
}
cleanup_on_exit ""
title "Module 01: build a cgroup by hand"
module_cleanup

# CPU used (millicores) and new throttled periods over N seconds, from cpu.stat.
measure() {
  local s=$1 u0 t0 u1 t1
  u0=$(node "awk '\$1==\"usage_usec\"{print \$2}' $CG/cpu.stat"); t0=$(node "awk '\$1==\"nr_throttled\"{print \$2}' $CG/cpu.stat")
  sleep "$s"
  u1=$(node "awk '\$1==\"usage_usec\"{print \$2}' $CG/cpu.stat"); t1=$(node "awk '\$1==\"nr_throttled\"{print \$2}' $CG/cpu.stat")
  echo "$(( (u1 - u0) / s / 1000 )) $(( t1 - t0 ))"
}

note "Step 1: which controllers can child cgroups use?"
step "docker exec $WORKER cat /sys/fs/cgroup/cgroup.subtree_control"
node "cat /sys/fs/cgroup/cgroup.subtree_control" | sed 's/^/  /'

note ""
note "Step 2: create a cgroup. It's just a folder."
step "docker exec $WORKER mkdir $CG"
node "mkdir $CG"
step "docker exec $WORKER ls $CG | head"
node "ls $CG | head -n 8" | sed 's/^/  /'
note "  The kernel filled the folder with control files the moment it was created."

note ""
note "Step 3: give it a CPU limit of 20 ms per 100 ms (a fifth of one CPU)"
step "docker exec $WORKER sh -c 'echo \"20000 100000\" > $CG/cpu.max'"
node "echo '20000 100000' > $CG/cpu.max"
echo "  $(node "cat $CG/cpu.max")"

note ""
note "Step 4: start a busy loop and move it into the cgroup"
step "docker exec -d $WORKER sh -c 'echo \$\$ > $CG/cgroup.procs; while :; do :; done'"
docker exec -d "$WORKER" sh -c "echo \$\$ > $CG/cgroup.procs; while :; do :; done"
sleep 1
pid=$(node "cat $CG/cgroup.procs" | head -n1)
echo "  cgroup.procs: $pid"
note "  Writing a PID into cgroup.procs is how any process joins a cgroup. That's all a runtime does too."

note ""
note "Step 5: watch the kernel hold it to 200m"
read -r cpu1 thr1 <<<"$(measure 5)"
step "cpu.stat over 5 seconds"
printf '  CPU used: %sm   throttled periods: %s\n' "$cpu1" "$thr1"

note ""
note "Step 6: change the limit while it runs"
step "docker exec $WORKER sh -c 'echo \"50000 100000\" > $CG/cpu.max'"
node "echo '50000 100000' > $CG/cpu.max"
read -r cpu2 thr2 <<<"$(measure 5)"
printf '  CPU used: %sm   throttled periods: %s\n' "$cpu2" "$thr2"
note "  No restart, no API call. The kernel picked up the new number straight away."

note ""
note "Step 7: a memory limit, and what happens when it's crossed"
node "mkdir $MG && echo 50M > $MG/memory.max && { [ -f $MG/memory.swap.max ] && echo 0 > $MG/memory.swap.max; true; }"
step "docker exec $WORKER cat $MG/memory.max"
echo "  $(node "cat $MG/memory.max")"
step "docker exec $WORKER sh -c 'echo \$\$ > $MG/cgroup.procs; a=x; while :; do a=\$a\$a; done'"
note "  A shell that keeps doubling a string, so its memory doubles every step..."
docker exec "$WORKER" sh -c "echo \$\$ > $MG/cgroup.procs; a=x; while :; do a=\$a\$a; done" >/dev/null 2>&1 && rc=0 || rc=$?
echo "  exit code: $rc"
step "docker exec $WORKER cat $MG/memory.events"
node "cat $MG/memory.events" | sed 's/^/  /'
kills=$(node "awk '\$1==\"oom_kill\"{print \$2}' $MG/memory.events")

title "Checks"
[ "$thr1" -gt 0 ] && pass "the busy loop was throttled ($thr1 periods in 5s)" || fail "no throttling seen"
[ "$cpu1" -le 230 ] && pass "CPU stayed near the 200m limit (${cpu1}m)" || fail "CPU was ${cpu1}m, above the 200m limit"
[ "$cpu2" -ge 400 ] && [ "$cpu2" -le 560 ] && pass "after the change it used about 500m (${cpu2}m)" || fail "after the change it used ${cpu2}m, expected about 500m"
[ "${kills:-0}" -ge 1 ] && pass "memory.events recorded an OOM kill" || fail "no OOM kill recorded"
[ "$rc" = "137" ] && pass "the process was killed with SIGKILL (exit code 137)" || note "exit code was $rc"

finish
