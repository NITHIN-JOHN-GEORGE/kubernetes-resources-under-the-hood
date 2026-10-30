#!/usr/bin/env bash
# make check-setup: is everything ready, and is anything left over from earlier labs?
set -uo pipefail
C="${CLUSTER:-under-the-hood}"; W="$C-worker"; bad=0
ok()  { printf '\033[32m✓\033[0m %s\n' "$1"; }
no()  { printf '\033[31m✗\033[0m %s\n    Fix: %s\n' "$1" "$2"; bad=1; }

if docker info >/dev/null 2>&1; then
  cpus=$(docker info --format '{{.NCPU}}'); mem=$(docker info --format '{{.MemTotal}}')
  gb=$(awk -v m="$mem" 'BEGIN{printf "%.1f", m/1024/1024/1024}')
  if [ "$cpus" -ge 4 ] && [ "$mem" -ge 5800000000 ]; then ok "Docker running ($cpus CPUs, $gb GB)"
  else no "Docker has $cpus CPUs and $gb GB" "give Docker at least 4 CPUs and 6 GB (Docker Desktop → Settings → Resources)"; fi
else no "Docker isn't running" "start Docker Desktop"; fi

for t in kind kubectl; do command -v $t >/dev/null || no "$t is not installed" "brew install $t (or see the README for WSL2)"; done
if command -v kind >/dev/null && command -v kubectl >/dev/null; then
  kv=$(kind version | awk '{print $2}'); cv=$(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"\(v[0-9.]*\)".*/\1/p' | head -1)
  minor=$(echo "$cv" | cut -d. -f2)
  if [ "${minor:-0}" -ge 32 ]; then ok "kind $kv, kubectl $cv"; else no "kubectl $cv is too old" "install kubectl 1.32 or newer (needed for in-place resize)"; fi
fi

if kind get clusters 2>/dev/null | grep -qx "$C"; then
  ready=$(kubectl --context "kind-$C" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
  profile=$(kubectl --context "kind-$C" get node "$W" -o jsonpath='{.metadata.labels.lab-profile}' 2>/dev/null)
  [ "$ready" = 2 ] && ok "Cluster $C: 2 nodes Ready (profile ${profile:-unknown})" || no "Cluster $C: only $ready node(s) Ready" "wait a minute, or make clean && make cluster"
  fs=$(docker exec "$W" stat -fc %T /sys/fs/cgroup 2>/dev/null)
  drv=$(docker exec "$W" sh -c "grep -h '^cgroupDriver' /var/lib/kubelet/config.yaml" 2>/dev/null | awk '{print $2}')
  [ "$fs" = cgroup2fs ] && [ "$drv" = systemd ] && ok "cgroups v2, $drv driver" || no "cgroup fs '$fs', driver '$drv'" "use cgroups v2 (on WSL2, see the README)"
  docker exec "$W" crictl images 2>/dev/null | grep -q lab-tools && ok "lab-tools image loaded" || no "lab-tools image is not on the worker" "make cluster"
  left=$(docker exec "$W" sh -c 'ls -d /sys/fs/cgroup/lab-* 2>/dev/null')
  for d in $left; do no "Leftover cgroup: $d" "make reset"; done
  taint=$(kubectl --context "kind-$C" get node "$W" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null)
  case "$taint" in *memory-pressure*) no "The worker still has a memory-pressure taint" "wait a minute, or make reset";; esac
  for ns in lab-checkpoints lab-quota lab-limits; do
    kubectl --context "kind-$C" get ns "$ns" >/dev/null 2>&1 && no "Namespace $ns is still around" "make reset"
  done
  n=$(kubectl --context "kind-$C" -n lab get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = 0 ] || printf '  (%s pod(s) running in namespace lab; that is fine if you are mid-lab)\n' "$n"
else
  no "No cluster named $C" "make cluster   (labs 01–07 only need Docker)"
fi
for c in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^lab-' ); do no "Leftover container: $c" "make reset"; done
[ "$bad" = 0 ] && echo "All good." || exit 1
