#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod psi-cpu labs/19-metrics-and-psi/; need_pod psi-memory labs/19-metrics-and-psi/
c=$(cg psi-cpu cpu.pressure | awk '/^some/{split($2,a,"="); print int(a[2])}')
[ "${c:-0}" -ge 20 ] && pass "psi-cpu: some avg10=$c% (threads waiting for a CPU)" || fail "psi-cpu's cpu.pressure some avg10 should be high (got ${c:-?})"
m=$(cg psi-memory memory.pressure | awk '/^some/{split($5,a,"="); print a[2]}')
[ "${m:-0}" != 0 ] && pass "psi-memory: memory.pressure total=$m µs of waiting" || fail "psi-memory should show some memory pressure"
finish
