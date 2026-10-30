#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"
for p in qos-guaranteed qos-burstable qos-besteffort; do need_pod $p labs/11-the-cgroup-tree/pods.yaml; done
case "$(pod_cgroup_dir qos-burstable)" in *burstable.slice/*) pass "qos-burstable sits in the burstable box";; *) fail "qos-burstable should be under the burstable slice";; esac
case "$(pod_cgroup_dir qos-besteffort)" in *besteffort.slice/*) pass "qos-besteffort sits in the besteffort box";; *) fail "qos-besteffort should be under the besteffort slice";; esac
case "$(pod_cgroup_dir qos-guaranteed)" in *burstable*|*besteffort*) fail "qos-guaranteed should sit directly under kubepods";; *kubepods*) pass "qos-guaranteed sits directly under the box for all pods";; *) fail "could not find qos-guaranteed's cgroup";; esac
[ "$(kubectl -n "$NS" exec qos-guaranteed -- cat /proc/1/oom_score_adj)" = -997 ] && pass "Guaranteed: oom_score_adj -997" || fail "Guaranteed should be -997"
[ "$(kubectl -n "$NS" exec qos-besteffort -- cat /proc/1/oom_score_adj)" = 1000 ] && pass "BestEffort: oom_score_adj 1000" || fail "BestEffort should be 1000"
finish
