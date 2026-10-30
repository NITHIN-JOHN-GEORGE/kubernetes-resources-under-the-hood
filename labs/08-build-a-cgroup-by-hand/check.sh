#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
on_node 'test -d /sys/fs/cgroup/lab-cpu' || { fail "/sys/fs/cgroup/lab-cpu not found on the worker. Run steps 1 to 5."; finish; }
[ "$(on_node 'cat /sys/fs/cgroup/lab-cpu/cpu.max')" = "50000 100000" ] && pass "lab-cpu's cpu.max is 50000 100000 (step 5)" || fail "lab-cpu's cpu.max should be 50000 100000 after step 5"
n=$(on_node 'cat /sys/fs/cgroup/lab-cpu/cgroup.procs | wc -l')
[ "${n:-0}" -ge 1 ] && pass "a process is inside lab-cpu" || fail "no process in lab-cpu (step 3)"
thr=$(on_node "awk '\$1==\"nr_throttled\"{print \$2}' /sys/fs/cgroup/lab-cpu/cpu.stat")
[ "${thr:-0}" -gt 10 ] && pass "it was throttled in $thr periods" || fail "expected throttling in lab-cpu (nr_throttled=${thr:-?})"
if on_node 'test -d /sys/fs/cgroup/lab-mem'; then
  k=$(on_node "awk '\$1==\"oom_kill\"{print \$2}' /sys/fs/cgroup/lab-mem/memory.events")
  [ "${k:-0}" -ge 1 ] && pass "lab-mem recorded an OOM kill" || fail "lab-mem should show oom_kill 1 (step 6)"
else fail "/sys/fs/cgroup/lab-mem not found (step 6)"; fi
finish
