#!/usr/bin/env bash
# Module 07: not all memory is equal. File cache is counted but can be reclaimed;
# memory a program allocates for itself can't, and that's what gets OOM-killed.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=mem-lab
node() { docker exec "$WORKER" sh -c "$1"; }

cleanup_on_exit module=07
title "Module 07: memory, properly"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true
apply "$dir/pod.yaml"
wait_ready "$pod"
pdir="$(pod_cgroup_dir "$pod")"

# Print current, anon, file, inactive_file and the working set (in MiB) from the container's own files.
snapshot() {
  kubectl -n "$NS" exec "$pod" -- sh -c '
    cur=$(cat /sys/fs/cgroup/memory.current)
    eval "$(awk "\$1==\"anon\"||\$1==\"file\"||\$1==\"inactive_file\"{print \$1\"=\"\$2}" /sys/fs/cgroup/memory.stat)"
    ws=$((cur - inactive_file))
    echo "$((cur/1048576)) $((anon/1048576)) $((file/1048576)) $((inactive_file/1048576)) $((ws/1048576))"'
}
show() { printf '  %-28s current %4s MiB | anon %4s | file %4s | inactive_file %4s | working set %4s\n' "$1" $2; }

note "Step 1: a fresh container"
step "kubectl -n $NS exec $pod -- cat /sys/fs/cgroup/memory.current; grep -E '^(anon|file|inactive_file) ' memory.stat"
s0="$(snapshot)"; show "at start:" "$s0"
note "  anon = memory programs asked for themselves. file = cached file data (page cache)."

note ""
note "Step 2: read 192 MiB of files through a 128 MiB limit"
step "kubectl -n $NS exec $pod -- sh -c '<write a 192 MiB file in 16 MiB steps>; cat /tmp/f > /dev/null'"
kubectl -n "$NS" exec "$pod" -- sh -c 'i=0; while [ $i -lt 12 ]; do dd if=/dev/zero of=/tmp/f bs=1M count=16 seek=$((i*16)) conv=notrunc,fsync 2>/dev/null; i=$((i+1)); done; cat /tmp/f > /dev/null; cat /tmp/f > /dev/null'
s1="$(snapshot)"; show "after reading the file:" "$s1"
step "docker exec $WORKER cat <pod cgroup>/memory.events"
node "cat $pdir/memory.events" | sed 's/^/  /'
max1=$(node "awk '\$1==\"max\"{print \$2}' $pdir/memory.events"); oom1=$(node "awk '\$1==\"oom_kill\"{print \$2}' $pdir/memory.events")
note "  Usage climbed to the limit, the kernel reclaimed cache over and over ('max' went up), and nothing died."
note "  The working set (current - inactive_file) is what the kubelet and most dashboards watch."

note ""
note "Step 3: now allocate memory the kernel can't throw away"
step "docker exec $WORKER cat <container cgroup>/memory.oom.group"
cdir="$(node "ls -d $pdir/cri-containerd-*.scope" | head -n1)"
echo "  $(node "cat $cdir/memory.oom.group")"
note "  1 = if one process in the container is OOM-killed, kill the whole container."
step "kubectl -n $NS exec $pod -- sh -c 'a=x; while :; do a=\$a\$a; done'"
kubectl -n "$NS" exec "$pod" -- sh -c 'a=x; while :; do a=$a$a; done' >/dev/null 2>&1 && rc=0 || rc=$?
echo "  kubectl exec exit code: $rc"
sleep 3
step "docker exec $WORKER cat <pod cgroup>/memory.events"
node "cat $pdir/memory.events" | sed 's/^/  /'
oom2=$(node "awk '\$1==\"oom_kill\"{print \$2}' $pdir/memory.events")
restarts="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
reason="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}')"
echo "  container restarts: $restarts   last termination: ${reason:-none}"

read -r c1 a1 f1 i1 w1 <<<"$s1"
title "Checks"
[ "${oom1:-0}" -eq 0 ] && pass "reading 192 MiB of files through a 128 MiB limit caused no OOM kill" || fail "an OOM kill happened during the file step"
[ "${max1:-0}" -gt 0 ] && pass "the cgroup hit memory.max and the kernel reclaimed ('max' $max1)" || fail "memory.max was never reached"
[ "$f1" -gt "$a1" ] && pass "after reading, most memory was file cache (${f1} MiB) not anon (${a1} MiB)" || fail "expected file cache to dominate"
[ "$w1" -lt "$c1" ] && pass "the working set (${w1} MiB) is below memory.current (${c1} MiB)" || fail "working set not below current"
[ "${oom2:-0}" -gt "${oom1:-0}" ] && pass "allocating anonymous memory ended in an OOM kill" || fail "no OOM kill after the anon step"
[ "$restarts" -ge 1 ] && pass "the whole container was killed and restarted (memory.oom.group)" || note "container restart count is $restarts"

finish
