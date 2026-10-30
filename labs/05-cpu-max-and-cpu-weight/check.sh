#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
docker inspect lab-box >/dev/null 2>&1 || { fail "container lab-box not found. Run the README's steps first."; finish; }
[ "$(in_box lab-box 'cat /sys/fs/cgroup/cpu.max')" = "50000 100000" ] && pass "cpu.max is 50000 100000 (--cpus=0.5)" || fail "cpu.max should be 50000 100000. Did you start lab-box with --cpus=0.5?"
[ "$(in_box lab-box 'cat /sys/fs/cgroup/memory.max')" = 134217728 ] && pass "memory.max is 134217728 (--memory=128m)" || fail "memory.max should be 134217728. Did you start lab-box with --memory=128m?"
[ "$(in_box lab-box 'cat /sys/fs/cgroup/cpu.weight')" = 100 ] && pass "cpu.weight is the default, 100" || fail "cpu.weight should be 100"
finish
