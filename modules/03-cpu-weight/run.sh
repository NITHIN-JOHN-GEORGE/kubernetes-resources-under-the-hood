#!/usr/bin/env bash
# Module 03: CPU requests become weights that split contended CPU.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
SAMPLE="${SAMPLE:-20}"

cleanup_on_exit module=03
title "Module 03: CPU weight under contention"
kubectl -n "$NS" delete pod -l module=03 --ignore-not-found >/dev/null 2>&1 || true

threads="$(on_node nproc)"
note "Worker node has $threads CPUs; each pod runs $threads busy loops so the CPUs are fully contended."
ensure_ns
step "sed s/__THREADS__/$threads/ pods.yaml | kubectl -n $NS apply -f -"
sed "s/__THREADS__/$threads/g" "$dir/pods.yaml" | kubectl -n "$NS" apply -f -
wait_ready weight-low
wait_ready weight-high

for p in weight-low weight-high; do
  step "kubectl -n $NS exec $p -- cat /sys/fs/cgroup/cpu.weight /sys/fs/cgroup/cpu.max"
  printf '  cpu.weight %s   cpu.max %s\n' "$(cg "$p" cpu.weight)" "$(cg "$p" cpu.max)"
done
note "Neither pod has a CPU limit, so neither is throttled. Only the weights differ: 100m vs 800m."

sleep 3
l0="$(cg_key weight-low cpu.stat usage_usec)"; h0="$(cg_key weight-high cpu.stat usage_usec)"; t0=$SECONDS
note "Measuring CPU time for about ${SAMPLE}s..."
sleep "$SAMPLE"
l1="$(cg_key weight-low cpu.stat usage_usec)"; h1="$(cg_key weight-high cpu.stat usage_usec)"; elapsed=$((SECONDS - t0))
low=$(( (l1 - l0) / elapsed / 1000 )); high=$(( (h1 - h0) / elapsed / 1000 ))
ratio_x10=$(( high * 10 / (low > 0 ? low : 1) ))
wl="$(cg weight-low cpu.weight)"; wh="$(cg weight-high cpu.weight)"; wratio_x10=$(( wh * 10 / (wl > 0 ? wl : 1) ))

step "CPU used over ${elapsed}s (millicores)"
printf '  weight-low   (request 100m)  %sm\n' "$low"
printf '  weight-high  (request 800m)  %sm\n' "$high"
printf '  CPU split high/low           %s.%sx\n' "$((ratio_x10 / 10))" "$((ratio_x10 % 10))"
printf '  request ratio                8.0x  (800m / 100m)\n'
printf '  cpu.weight ratio             %s.%sx  (%s / %s)\n' "$((wratio_x10 / 10))" "$((wratio_x10 % 10))" "$wh" "$wl"
note "Under contention the bigger request wins a proportionally bigger share of CPU."
note "cpu.weight is not always proportional to the request: newer runtimes convert CPU shares"
note "to cpu.weight with a non-linear formula. The exact split also depends on other load on the node."

title "Checks"
[ "$(cg weight-low cpu.max | cut -d' ' -f1)" = "max" ] && pass "no CPU quota on either pod" || fail "unexpected CPU quota"
[ "$(cg weight-high cpu.weight)" -gt "$(cg weight-low cpu.weight)" ] && pass "weight-high has the higher cpu.weight" || fail "cpu.weight values are not ordered as expected"
[ "$ratio_x10" -ge 30 ] && pass "weight-high got at least 3x the CPU of weight-low" || fail "CPU split was only $((ratio_x10 / 10)).$((ratio_x10 % 10))x"

finish
