#!/usr/bin/env bash
# Module 11: pressure stall information (PSI) measures time lost waiting for CPU, memory and IO.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
SAMPLE="${SAMPLE:-20}"

cleanup_on_exit module=11
title "Module 11: pressure stall information (PSI)"
kubectl -n "$NS" delete pod -l module=11 --ignore-not-found >/dev/null 2>&1 || true

if ! on_node "[ -f /proc/pressure/cpu ]"; then
  note "SKIP: this kernel doesn't expose /proc/pressure (CONFIG_PSI is off or psi=0 on the kernel command line)."
  exit 0
fi

step "docker exec $WORKER cat /proc/pressure/cpu   (before)"
on_node "cat /proc/pressure/cpu" | sed 's/^/  /'

threads=$(( $(on_node nproc) * 2 ))
ensure_ns
step "sed s/__THREADS__/$threads/ pods.yaml | kubectl -n $NS apply -f -"
sed "s/__THREADS__/$threads/g" "$dir/pods.yaml" | kubectl -n "$NS" apply -f -
show_pods psi-cpu psi-memory
wait_ready psi-cpu
wait_ready psi-memory
note "Letting pressure build for ${SAMPLE}s (avg10 is a 10-second moving average)..."
sleep "$SAMPLE"

# Never let one unreadable file stop the module.
safe_cg() { cg "$1" "$2" 2>/dev/null || echo "unavailable"; }
for p in psi-cpu psi-memory; do
  for f in cpu.pressure memory.pressure io.pressure; do
    step "kubectl -n $NS exec $p -- cat /sys/fs/cgroup/$f"
    safe_cg "$p" "$f" | sed 's/^/  /'
  done
done
restarts="$(kubectl -n "$NS" get pod psi-memory -o jsonpath='{.status.containerStatuses[0].restartCount}')"
note "some = share of time at least one task in the cgroup was stalled on that resource."
note "full = share of time ALL non-idle tasks were stalled at once (no progress at all)."

step "docker exec $WORKER cat /proc/pressure/cpu   (during)"
on_node "cat /proc/pressure/cpu" | sed 's/^/  /'

avg10() { safe_cg "$1" "$2" | awk '$1=="some" {for (i=2;i<=NF;i++) if ($i ~ /^avg10=/) {sub(/avg10=/,"",$i); print int($i)}}'; }
total() { safe_cg "$1" "$2" | awk '$1=="some" {for (i=2;i<=NF;i++) if ($i ~ /^total=/) {sub(/total=/,"",$i); print $i}}'; }
cpu_some="$(avg10 psi-cpu cpu.pressure)"
mem_total="$(total psi-memory memory.pressure)"

title "Checks"
[ "${cpu_some:-0}" -gt 10 ] && pass "psi-cpu cpu.pressure some avg10 is ${cpu_some}% (> 10%)" || fail "psi-cpu cpu.pressure some avg10 is only ${cpu_some}%"
[ "${restarts:-0}" = "0" ] && pass "psi-memory never restarted (no OOM kill)" || fail "psi-memory restarted $restarts time(s)"
if [ "${mem_total:-0}" -gt 0 ]; then
  pass "psi-memory has spent ${mem_total}us stalled on memory reclaim"
else
  note "INFO psi-memory shows no memory stall yet; reclaim of clean page cache can be cheap on a fast disk."
fi

finish
