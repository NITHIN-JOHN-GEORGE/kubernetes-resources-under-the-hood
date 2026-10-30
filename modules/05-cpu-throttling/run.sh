#!/usr/bin/env bash
# Module 05: CPU limits cause throttling, even when the node has idle CPUs.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
SAMPLE="${SAMPLE:-15}"

cleanup_on_exit module=05
title "Module 05: CPU throttling"
kubectl -n "$NS" delete pod -l module=05 --ignore-not-found >/dev/null 2>&1 || true
apply "$dir/pods.yaml"
wait_ready cpu-limited
wait_ready cpu-unlimited

for p in cpu-limited cpu-unlimited; do
  step "kubectl -n $NS exec $p -- cat /sys/fs/cgroup/cpu.max"
  cg "$p" cpu.max
done
note "cpu-limited: '20000 100000' = 20ms per 100ms period. cpu-unlimited: 'max' = no quota."

# Read cpu.stat once per pod so the counters are consistent with each other.
key() { printf '%s\n' "$1" | awk -v k="$2" '$1==k {print $2}'; }

note ""
note "Sampling cpu.stat for about ${SAMPLE}s while 4 busy loops run in each pod..."
L0="$(cg cpu-limited cpu.stat)"; U0="$(cg cpu-unlimited cpu.stat)"; t0=$SECONDS
for i in $(seq 1 "$SAMPLE"); do
  sleep 1
  printf '\r  t=%2ss  cpu-limited nr_throttled=%s' "$i" "$(cg_key cpu-limited cpu.stat nr_throttled)"
done
echo ""
L1="$(cg cpu-limited cpu.stat)"; U1="$(cg cpu-unlimited cpu.stat)"; elapsed=$((SECONDS - t0))

dl_periods=$(( $(key "$L1" nr_periods) - $(key "$L0" nr_periods) ))
dl_thr=$(( $(key "$L1" nr_throttled) - $(key "$L0" nr_throttled) ))
dl_use=$(( $(key "$L1" usage_usec) - $(key "$L0" usage_usec) ))
du_thr=$(( $(key "$U1" nr_throttled) - $(key "$U0" nr_throttled) ))
du_use=$(( $(key "$U1" usage_usec) - $(key "$U0" usage_usec) ))
# Limited pod: CPU per 100ms period is exact (usage / periods). Unlimited pod: usage / wall-clock time.
dl_cpu=$(( dl_periods > 0 ? dl_use / dl_periods / 100 : 0 ))
du_cpu=$(( du_use / (elapsed > 0 ? elapsed : 1) / 1000 ))

step "results over ${elapsed}s (${dl_periods} periods of 100ms)"
printf '  %-14s %-16s %-14s %s\n' "pod" "periods" "throttled" "CPU used (millicores)"
printf '  %-14s %-16s %-14s %s\n' "cpu-limited" "$dl_periods" "$dl_thr" "$dl_cpu"
printf '  %-14s %-16s %-14s %s\n' "cpu-unlimited" "-" "$du_thr" "$du_cpu"
note "The limited pod is throttled in almost every 100ms period and never gets past ~200m."
note "The unlimited pod has the same request but uses whatever idle CPU the node has."

title "Checks"
[ "$(cg cpu-limited cpu.max)" = "20000 100000" ] && pass "cpu-limited has cpu.max '20000 100000'" || fail "unexpected cpu.max on cpu-limited"
[ "$(cg cpu-unlimited cpu.max | cut -d' ' -f1)" = "max" ] && pass "cpu-unlimited has no CPU quota" || fail "cpu-unlimited unexpectedly has a quota"
[ "$dl_thr" -gt 0 ] && pass "cpu-limited was throttled in $dl_thr periods" || fail "cpu-limited was not throttled"
[ "$du_thr" -eq 0 ] && pass "cpu-unlimited was never throttled" || fail "cpu-unlimited was throttled $du_thr times"
[ "$dl_cpu" -le 230 ] && pass "cpu-limited stayed near its 200m limit (${dl_cpu}m)" || fail "cpu-limited used ${dl_cpu}m, above its limit"
[ "$du_cpu" -gt "$dl_cpu" ] && pass "cpu-unlimited used more CPU (${du_cpu}m) than cpu-limited" || fail "cpu-unlimited did not use more CPU"

finish
