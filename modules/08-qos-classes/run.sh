#!/usr/bin/env bash
# Module 08: QoS classes decide the cgroup slice and who the OOM killer picks first.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pods="qos-guaranteed qos-burstable qos-besteffort"

cleanup_on_exit module=08
title "Module 08: QoS classes"
kubectl -n "$NS" delete pod -l module=08 --ignore-not-found >/dev/null 2>&1 || true
apply "$dir/pods.yaml"
for p in $pods; do wait_ready "$p"; done

step "QoS class, cgroup slice and oom_score_adj for each pod"
printf '  %-16s %-12s %-14s %s\n' "pod" "qosClass" "oom_score_adj" "cgroup slice on the node"
info() { # pod -> "class adj dir"
  printf '%s %s %s' \
    "$(kubectl -n "$NS" get pod "$1" -o jsonpath='{.status.qosClass}')" \
    "$(kubectl -n "$NS" exec "$1" -c main -- cat /proc/1/oom_score_adj)" \
    "$(pod_cgroup_dir "$1")"
}
read -r G_CLASS G_ADJ G_DIR <<<"$(info qos-guaranteed)"
read -r B_CLASS B_ADJ B_DIR <<<"$(info qos-burstable)"
read -r E_CLASS E_ADJ E_DIR <<<"$(info qos-besteffort)"
printf '  %-16s %-12s %-14s %s\n' qos-guaranteed "$G_CLASS" "$G_ADJ" "${G_DIR#/sys/fs/cgroup/}"
printf '  %-16s %-12s %-14s %s\n' qos-burstable  "$B_CLASS" "$B_ADJ" "${B_DIR#/sys/fs/cgroup/}"
printf '  %-16s %-12s %-14s %s\n' qos-besteffort "$E_CLASS" "$E_ADJ" "${E_DIR#/sys/fs/cgroup/}"
note "Guaranteed pods get their own slice directly under the kubepods slice; the others sit under a per-class slice."
note "oom_score_adj tells the kernel who to kill first when the whole node runs out of memory:"
note "  Guaranteed -997 (last), Burstable 2..999 (bigger memory request = lower score), BestEffort 1000 (first)."

title "Checks"
[ "$G_CLASS" = "Guaranteed" ] && pass "qos-guaranteed is Guaranteed" || fail "qos-guaranteed is $G_CLASS"
[ "$B_CLASS" = "Burstable" ] && pass "qos-burstable is Burstable" || fail "qos-burstable is $B_CLASS"
[ "$E_CLASS" = "BestEffort" ] && pass "qos-besteffort is BestEffort" || fail "qos-besteffort is $E_CLASS"
[ "$G_ADJ" = "-997" ] && pass "Guaranteed oom_score_adj is -997" || fail "Guaranteed oom_score_adj is $G_ADJ"
[ "$E_ADJ" = "1000" ] && pass "BestEffort oom_score_adj is 1000" || fail "BestEffort oom_score_adj is $E_ADJ"
b="$B_ADJ"
[ "$b" -ge 2 ] && [ "$b" -le 999 ] && pass "Burstable oom_score_adj is $b (between 2 and 999)" || fail "Burstable oom_score_adj is $b"
case "$B_DIR" in *kubepods-burstable.slice/*) pass "Burstable pod lives under the burstable slice";; *) fail "unexpected Burstable slice";; esac
case "$E_DIR" in *kubepods-besteffort.slice/*) pass "BestEffort pod lives under the besteffort slice";; *) fail "unexpected BestEffort slice";; esac
case "$G_DIR" in *kubepods.slice/*kubepods-pod*) pass "Guaranteed pod lives directly under the kubepods slice";; *) fail "unexpected Guaranteed slice";; esac

finish
