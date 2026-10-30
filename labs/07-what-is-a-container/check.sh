#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
for c in lab-box lab-box2; do
  docker inspect $c >/dev/null 2>&1 || { fail "container $c not found. Run the README's steps first."; continue; }
  [ "$(in_box $c 'cat /proc/1/comm')" = sleep ] && pass "in $c, PID 1 is sleep" || fail "in $c, PID 1 should be sleep"
done
if docker inspect lab-box >/dev/null 2>&1; then
  pid=$(docker inspect lab-box --format '{{.State.Pid}}')
  [ "${pid:-0}" -gt 1 ] && pass "outside, lab-box's sleep is PID $pid" || fail "could not find lab-box's PID on the host"
  path=$(docker run --rm --pid=host --cgroupns=host lab-tools:1.0 cat /proc/$pid/cgroup 2>/dev/null)
  case "$path" in 0::/?*) pass "and its cgroup path is ${path#0::}";; *) fail "expected a long cgroup path outside, got '$path'";; esac
fi
finish
