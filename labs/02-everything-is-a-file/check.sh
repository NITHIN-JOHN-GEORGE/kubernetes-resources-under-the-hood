#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
docker inspect lab-box >/dev/null 2>&1 || { fail "container lab-box not found. Run the README's steps first."; finish; }
size=$(in_box lab-box "stat -c %s /proc/meminfo")
[ "$size" = 0 ] && pass "/proc/meminfo is 0 bytes on 'disk'" || fail "expected size 0, got '$size'"
in_box lab-box "grep -q MemTotal /proc/meminfo" && pass "and yet it holds MemTotal: the kernel makes the answer when you read it" || fail "could not read MemTotal"
finish
