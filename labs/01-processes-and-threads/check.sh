#!/usr/bin/env bash
# make check LAB=01: read-only checks on the lab-box container.
source "$(dirname "$0")/../../lib/common.sh"
docker inspect lab-box >/dev/null 2>&1 || { fail "container lab-box not found. Run the README's steps first."; finish; }
procs=$(in_box lab-box 'ps -eo pid= | wc -l')
threads=$(in_box lab-box 'ps -eLo lwp= | wc -l')
[ "${procs:-0}" -ge 5 ] && pass "lab-box runs $procs processes (serve + 4 workers, and ps itself)" || fail "expected at least 5 processes, saw ${procs:-0}"
[ "${threads:-0}" -gt "${procs:-0}" ] && pass "there are more threads ($threads) than processes: some processes have several" || fail "expected more threads than processes"
t1=$(in_box lab-box 'ls /proc/1/task | wc -l')
[ "${t1:-0}" -ge 1 ] && pass "/proc/1/task lists $t1 thread(s) for PID 1" || fail "could not read /proc/1/task"
finish
