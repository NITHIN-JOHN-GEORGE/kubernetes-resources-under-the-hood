#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod cpu-limited labs/14-limits-and-throttling/; need_pod cpu-unlimited labs/14-limits-and-throttling/
[ "$(cg cpu-limited cpu.max)" = "20000 100000" ] && pass "cpu-limited's cpu.max is 20000 100000" || fail "cpu-limited's cpu.max should be 20000 100000"
p1=$(cg_key cpu-limited cpu.stat nr_periods); t1=$(cg_key cpu-limited cpu.stat nr_throttled)
m=$(pod_millicores cpu-limited 5)
p2=$(cg_key cpu-limited cpu.stat nr_periods); t2=$(cg_key cpu-limited cpu.stat nr_throttled)
dp=$((p2-p1)); dt=$((t2-t1))
[ "$dp" -gt 0 ] && [ $(( dt * 100 / dp )) -ge 80 ] && pass "throttled in $dt of $dp periods" || fail "expected throttling in most periods ($dt of $dp)"
[ "$m" -le 230 ] && pass "held to about 200m (${m}m)" || fail "expected about 200m of CPU, got ${m}m"
[ "$(cg_key cpu-unlimited cpu.stat nr_throttled)" = 0 ] && pass "cpu-unlimited was never throttled" || fail "cpu-unlimited should have nr_throttled 0"
finish
