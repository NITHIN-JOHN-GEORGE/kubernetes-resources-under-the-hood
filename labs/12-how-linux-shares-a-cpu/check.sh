#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
need_pod share-a labs/12-how-linux-shares-a-cpu/; need_pod share-b labs/12-how-linux-shares-a-cpu/
[ "$(cg share-a cpu.weight)" = "$(cg share-b cpu.weight)" ] && pass "both pods have the same cpu.weight" || fail "the two pods should have the same cpu.weight"
a=$(pod_millicores share-a 5); b=$(pod_millicores share-b 5)
echo "  share-a ${a}m, share-b ${b}m (each measured over 5 s)"
lo=$(( a<b ? a : b )); hi=$(( a>b ? a : b ))
[ "$lo" -gt 0 ] && [ $(( hi * 100 / lo )) -le 140 ] && pass "they split the CPU roughly evenly" || fail "expected a roughly even split"
finish
