#!/usr/bin/env bash
# Shared helpers for every module. Source this file; do not run it directly.

set -euo pipefail

CLUSTER="${CLUSTER:-under-the-hood}"
NS="${NS:-lab}"
WORKER="${WORKER:-${CLUSTER}-worker}"
WAIT="${WAIT:-120s}"

if [ -t 1 ]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; GREEN=$'\e[32m'; RED=$'\e[31m'; CYAN=$'\e[36m'; RESET=$'\e[0m'
else
  BOLD=""; DIM=""; GREEN=""; RED=""; CYAN=""; RESET=""
fi

title()  { printf '\n%s== %s ==%s\n' "$BOLD" "$*" "$RESET"; }
step()   { printf '\n%s$ %s%s\n' "$CYAN" "$*" "$RESET"; }
note()   { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }
pass()   { printf '%sPASS%s %s\n' "$GREEN" "$RESET" "$*"; }
fail()   { printf '%sFAIL%s %s\n' "$RED" "$RESET" "$*"; FAILED=1; }
FAILED=0
finish() { if [ "$FAILED" -ne 0 ]; then exit 1; fi; }

# Run a command, printing it first so readers can copy it.
run() { step "$*"; "$@"; }

ensure_ns() { kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null; }

# Apply a manifest into the lab namespace.
apply() { ensure_ns; run kubectl -n "$NS" apply -f "$1"; }

wait_ready() { run kubectl -n "$NS" wait --for=condition=Ready "pod/$1" --timeout="$WAIT"; }

# Read a file inside the container's own cgroup (cgroups v2 + cgroup namespace:
# the container sees its own cgroup mounted at /sys/fs/cgroup).
cg() { kubectl -n "$NS" exec "$1" -c "${3:-main}" -- cat "/sys/fs/cgroup/$2"; }

# Print a cgroup file with a label.
show_cg() { printf '  %-22s %s\n' "$2" "$(cg "$1" "$2" "${3:-}" | tr '\n' ' ')"; }

# Read one key from a flat-keyed cgroup file such as cpu.stat or memory.events.
cg_key() { cg "$1" "$2" | awk -v k="$3" '$1==k {print $2}'; }

# Run a command on the worker node (the kind node is a Docker container).
on_node() { docker exec "$WORKER" sh -c "$*"; }

pod_uid() { kubectl -n "$NS" get pod "$1" -o jsonpath='{.metadata.uid}'; }

# The kubelet's pod tree. On a normal node it is /sys/fs/cgroup/kubepods.slice; kind runs the
# kubelet with cgroupRoot=/kubelet, so there it is /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice.
kubepods_root() {
  on_node "find /sys/fs/cgroup -maxdepth 2 -type d -name '*kubepods.slice' | head -n1"
}

# Directory of a pod's cgroup on the node (systemd driver: dashes in the UID become underscores).
pod_cgroup_dir() {
  local uid root; uid="$(pod_uid "$1" | tr '-' '_')"; root="$(kubepods_root)"
  on_node "find '$root' -maxdepth 2 -type d -name '*pod${uid}.slice' | head -n1"
}

# Delete a module's pods when the script exits: on success, on failure and on Ctrl-C.
# Set KEEP=1 to leave them running so you can explore.
cleanup_on_exit() {
  CLEAN_SELECTOR="$1"
  trap _cleanup EXIT
}
_cleanup() {
  local rc=$?
  # Modules can define module_cleanup for extra work (restore kubelet config, delete a namespace).
  if declare -F module_cleanup >/dev/null; then module_cleanup || true; fi
  if [ "${KEEP:-0}" != "1" ] && [ -n "${CLEAN_SELECTOR:-}" ]; then
    kubectl -n "$NS" delete pod -l "$CLEAN_SELECTOR" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    note ""
    note "Cleaned up the module's pods. Run with KEEP=1 to keep them."
  fi
  exit "$rc"
}

# ---------------------------------------------------------------------------
# Kubelet config changes on the worker node (modules 07 and 11).
# The original config is backed up once and always restored by kubelet_restore.
# ---------------------------------------------------------------------------
KUBELET_CFG=/var/lib/kubelet/config.yaml

wait_node_ready() {
  sleep 5
  kubectl wait --for=condition=Ready "node/$WORKER" --timeout=180s >/dev/null
}

kubelet_backup() {
  on_node "[ -f $KUBELET_CFG.lab-backup ] || cp $KUBELET_CFG $KUBELET_CFG.lab-backup"
}

kubelet_restart() {
  on_node "systemctl restart kubelet"
  wait_node_ready
}

# Set a top-level scalar, e.g. kubelet_set podPidsLimit 64
kubelet_set() {
  on_node "if grep -q '^$1:' $KUBELET_CFG; then sed -i 's|^$1:.*|$1: $2|' $KUBELET_CFG; else echo '$1: $2' >> $KUBELET_CFG; fi"
}

# Replace the whole evictionHard map. Pass entries as key=value, e.g. memory.available=500Mi
kubelet_set_eviction_hard() {
  local add="echo 'evictionHard:' >> $KUBELET_CFG;"
  for kv in "$@"; do add="$add echo '  ${kv%%=*}: \"${kv#*=}\"' >> $KUBELET_CFG;"; done
  on_node "awk 'BEGIN{skip=0} /^evictionHard:/{skip=1; next} skip && /^[[:space:]]/{next} {skip=0; print}' $KUBELET_CFG > $KUBELET_CFG.tmp && mv $KUBELET_CFG.tmp $KUBELET_CFG && $add"
}

kubelet_restore() {
  if on_node "[ -f $KUBELET_CFG.lab-backup ]"; then
    on_node "mv $KUBELET_CFG.lab-backup $KUBELET_CFG"
    kubelet_restart
    note "Restored the worker's original kubelet config."
  fi
}

# Print a kubelet config value as the running kubelet sees it (from configz).
kubelet_live() {
  local raw; raw="$(kubectl get --raw "/api/v1/nodes/$WORKER/proxy/configz")"
  printf '%s' "$raw" | grep -o "\"$1\":{[^}]*}" | head -n1 && return 0
  printf '%s' "$raw" | grep -o "\"$1\":[^,}]*" | head -n1
}

# Wait until the lab namespace has no pods left (so earlier modules don't skew scheduling).
wait_lab_empty() {
  kubectl -n "$NS" wait --for=delete pod --all --timeout=90s >/dev/null 2>&1 || true
}

# Sum of CPU requests (millicores) of non-terminated pods on the worker.
worker_cpu_requested() {
  kubectl get pods -A --field-selector "spec.nodeName=$WORKER,status.phase!=Succeeded,status.phase!=Failed" \
    -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.cpu}{"\n"}{end}{end}' |
    awk '/m$/ {sub(/m$/,""); s+=$1; next} /^[0-9.]+$/ {s+=$1*1000} END {print int(s)}'
}

# Allocatable CPU of the worker in millicores.
worker_cpu_allocatable() {
  kubectl get node "$WORKER" -o jsonpath='{.status.allocatable.cpu}' |
    awk '/m$/ {sub(/m$/,""); print int($1); next} {print int($1*1000)}'
}

# Kubernetes server minor version, e.g. 33
server_minor() {
  kubectl version -o yaml 2>/dev/null | awk '/serverVersion:/{f=1} f && /minor:/ {gsub(/[^0-9]/,"",$2); print $2; exit}'
}
