#!/usr/bin/env bash
# Module 02: follow one pod from YAML down to the cgroup files, through every layer.
source "$(dirname "$0")/../../lib/common.sh"
dir="$(dirname "$0")"
pod=follow-me
node() { docker exec "$WORKER" sh -c "$1"; }

cleanup_on_exit module=02
title "Module 02: follow one pod down to the kernel"
kubectl -n "$NS" delete pod "$pod" --ignore-not-found >/dev/null 2>&1 || true

note "Layer 1, the API: you ask for 250m/64Mi, limited to 500m/128Mi"
apply "$dir/pod.yaml"
wait_ready "$pod"

cid="$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].containerID}')"; cid="${cid#containerd://}"
step "kubectl -n $NS get pod $pod -o jsonpath='{.status.containerStatuses[0].containerID}'"
echo "  containerd://${cid:0:12}…"

note ""
note "Layer 2, the container runtime: what the kubelet asked containerd for (the OCI spec)"
step "docker exec $WORKER crictl inspect <id> | grep -E 'cgroupsPath|shares|quota|period|\"limit\"'"
spec="$(node "crictl inspect $cid" | grep -E '"cgroupsPath"|"shares"|"quota"|"period"|"limit"' | sed 's/^ *//' | head -n 8)"
echo "$spec" | sed 's/^/  /'
note "  cpu shares 256 = 250m × 1024 / 1000: the kubelet still speaks in cgroup v1 units."
note "  The runtime converts them to cgroup v2 values when it creates the cgroup."

note ""
note "Layer 3, systemd: the container is a systemd 'scope' with these properties"
step "docker exec $WORKER systemctl show cri-containerd-<id>.scope -p CPUWeight -p CPUQuotaPerSecUSec -p MemoryMax"
props="$(node "systemctl show cri-containerd-$cid.scope -p CPUWeight -p CPUQuotaPerSecUSec -p MemoryMax")"
echo "$props" | sed 's/^/  /'

note ""
note "Layer 4, the kernel: the files systemd wrote"
cdir="$(pod_cgroup_dir "$pod")/cri-containerd-$cid.scope"
step "docker exec $WORKER cat <container cgroup>/{cpu.weight,cpu.max,memory.max}"
echo "  ${cdir#/sys/fs/cgroup/}" | sed 's/cri-containerd-\(.\{12\}\).*/cri-containerd-\1….scope/'
weight="$(node "cat $cdir/cpu.weight")"; cpumax="$(node "cat $cdir/cpu.max")"; memmax="$(node "cat $cdir/memory.max")"
printf '  cpu.weight %s\n  cpu.max    %s\n  memory.max %s\n' "$weight" "$cpumax" "$memmax"

note ""
note "And the process itself: one sleep, seen from both sides"
hpid="$(node "cat $cdir/cgroup.procs" | head -n1)"
step "on the node:  cat <container cgroup>/cgroup.procs; cat /proc/<pid>/comm; cat /proc/<pid>/cgroup"
printf '  PID %s  %s\n' "$hpid" "$(node "cat /proc/$hpid/comm")"
hcg="$(node "cat /proc/$hpid/cgroup")"; echo "  $hcg" | sed 's/cri-containerd-\(.\{12\}\).*/cri-containerd-\1….scope/'
step "in the pod:   kubectl exec $pod -- cat /proc/1/comm /proc/self/cgroup"
ccomm="$(kubectl -n "$NS" exec "$pod" -- cat /proc/1/comm)"; ccg="$(kubectl -n "$NS" exec "$pod" -- cat /proc/self/cgroup)"
printf '  PID 1  %s\n  %s\n' "$ccomm" "$ccg"
note "  Same process. The PID namespace gives it a different number inside; the cgroup namespace"
note "  makes its deep cgroup path look like '/'."

title "Checks"
case "$spec" in *cgroupsPath*"$(pod_uid "$pod" | tr '-' '_')"*) pass "the runtime spec's cgroupsPath names this pod";; *) fail "cgroupsPath doesn't mention the pod";; esac
case "$spec" in *'"shares": 256'*) pass "the kubelet asked for 256 CPU shares (250m)";; *) fail "expected 256 CPU shares in the runtime spec";; esac
case "$props" in *CPUQuotaPerSecUSec=500ms*) pass "systemd holds the 500m limit as 500ms per second";; *) fail "systemd CPU quota is not 500ms";; esac
[ "$cpumax" = "50000 100000" ] && pass "cpu.max is 50000 100000" || fail "cpu.max is $cpumax"
[ "$memmax" = "134217728" ] && pass "memory.max is 134217728" || fail "memory.max is $memmax"
case "$props" in *"CPUWeight=$weight"*) pass "systemd's CPUWeight matches cpu.weight ($weight)";; *) fail "CPUWeight and cpu.weight differ";; esac
[ "$hpid" != "1" ] && [ "$ccomm" = "sleep" ] && pass "the same sleep is PID $hpid on the node and PID 1 in the pod" || fail "PID view mismatch"
[ "$ccg" = "0::/" ] && pass "inside the pod, the cgroup path reads 0::/" || fail "inside the pod, /proc/self/cgroup is $ccg"

finish
