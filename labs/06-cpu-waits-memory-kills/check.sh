#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
if docker inspect lab-cpu >/dev/null 2>&1; then
  thr=$(in_box lab-cpu "awk '\$1==\"nr_throttled\"{print \$2}' /sys/fs/cgroup/cpu.stat")
  [ "${thr:-0}" -gt 10 ] && pass "lab-cpu was throttled in $thr periods" || fail "lab-cpu should be throttled (nr_throttled=${thr:-?})"
  [ "$(docker inspect lab-cpu --format '{{.State.Running}}')" = true ] && pass "and it's still running: CPU limits never kill" || fail "lab-cpu should still be running"
else fail "container lab-cpu not found. Run the CPU step first."; fi
if docker inspect lab-mem >/dev/null 2>&1; then
  [ "$(docker inspect lab-mem --format '{{.State.OOMKilled}}')" = true ] && pass "lab-mem was OOM-killed" || fail "lab-mem should have been OOM-killed"
  [ "$(docker inspect lab-mem --format '{{.State.ExitCode}}')" = 137 ] && pass "with exit code 137 (SIGKILL)" || fail "expected exit code 137"
else fail "container lab-mem not found. Run the memory step first."; fi
finish
