#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
docker inspect lab-box >/dev/null 2>&1 || { fail "container lab-box not found. Run the README's steps first."; finish; }
[ "$(in_box lab-box 'cat /proc/self/comm')" = cat ] && pass "/proc/self/comm names the process reading it (cat)" || fail "/proc/self/comm should print cat"
[ "$(in_box lab-box 'cat /proc/self/cgroup')" = "0::/" ] && pass "/proc/self/cgroup reads 0::/ inside the container" || fail "expected 0::/ from /proc/self/cgroup"
finish
