#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
docker inspect lab-box >/dev/null 2>&1 || { fail "container lab-box not found. Run the README's steps first."; finish; }
[ "$(in_box lab-box 'stat -fc %T /sys/fs/cgroup')" = cgroup2fs ] && pass "/sys/fs/cgroup is cgroups v2" || fail "expected cgroup2fs (cgroups v2)"
in_box lab-box 'mount | grep " /sys/fs/cgroup " | grep -q "(ro,"' && pass "it's mounted read-only inside the container" || fail "expected a read-only mount"
finish
