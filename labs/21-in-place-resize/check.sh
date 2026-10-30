#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod resize-demo labs/21-in-place-resize/
[ "$(cg resize-demo cpu.max)" = "50000 100000" ] && pass "cpu.max is now 50000 100000 (500m)" || fail "cpu.max should be 50000 100000 after the resize"
[ "$(cg resize-demo memory.max)" = 134217728 ] && pass "memory.max is now 134217728 (128Mi)" || fail "memory.max should be 134217728 after the resize"
[ "$(kubectl -n "$NS" get pod resize-demo -o jsonpath='{.status.containerStatuses[0].restartCount}')" = 0 ] && pass "and the container never restarted" || fail "the container restarted"
finish
