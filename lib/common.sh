#!/usr/bin/env bash
# Shared helpers for check.sh, answer.sh and the incident scripts. Source it; don't run it.
set -u
CLUSTER="${CLUSTER:-under-the-hood}"
WORKER="${WORKER:-${CLUSTER}-worker}"
NS="${NS:-lab}"
if [ -t 1 ]; then GREEN=$'\e[32m'; RED=$'\e[31m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'; else GREEN=""; RED=""; BOLD=""; DIM=""; RESET=""; fi
FAILED=0
pass()   { printf '%sPASS%s %s\n' "$GREEN" "$RESET" "$*"; }
fail()   { printf '%sFAIL%s %s\n' "$RED" "$RESET" "$*"; FAILED=1; }
title()  { printf '\n%s== %s ==%s\n' "$BOLD" "$*" "$RESET"; }
note()   { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }
finish() { [ "$FAILED" = 0 ] || { echo; echo "Some checks failed. Compare your steps with the README, or run: make test LAB=${LAB:-N}"; exit 1; }; }

# Is this pod there and running? Prints a FAIL telling the reader which step to run if not.
need_pod() { kubectl -n "$NS" get pod "$1" >/dev/null 2>&1 || { fail "pod $1 not found. Run the README's first step: kubectl apply -f ${2:-the lab folder}"; finish; }; }

# Read a cgroup file from inside a pod's container.
cg() { kubectl -n "$NS" exec "$1" -c "${3:-main}" -- cat "/sys/fs/cgroup/$2" 2>/dev/null; }
cg_key() { cg "$1" "$2" | awk -v k="$3" '$1==k {print $2}'; }

# Run a command on the worker node (a kind node is a Docker container).
on_node() { docker exec "$WORKER" sh -c "$*"; }

# The pod's cgroup folder on the node.
pod_cgroup_dir() { "$(dirname "${BASH_SOURCE[0]}")/../scripts/pod-cgroup.sh" "$1" "$NS"; }

# The kubelet's box for all pods: kubepods.slice, or kubelet.slice/kubelet-kubepods.slice on kind.
kubepods_root() { on_node "find /sys/fs/cgroup -maxdepth 2 -type d -name '*kubepods.slice' | head -n1"; }

# Read a key from a file in a Docker container (labs 01–07).
in_box() { docker exec "$1" sh -c "$2" 2>/dev/null; }

# --- Used by the incident scripts ---
CYAN=$'\e[36m'; [ -t 1 ] || CYAN=""
step()   { printf '\n%s$ %s%s\n' "$CYAN" "$*" "$RESET"; }
run()    { step "$*"; "$@"; }
ensure_ns() { kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null; }
# Apply a manifest into the lab namespace, then say what each pod is for.
apply() {
  ensure_ns
  run kubectl -n "$NS" apply -f "$1"
  local pods; pods="$(kubectl apply --dry-run=client -o name -f "$1" | sed -n 's#^pod/##p')"
  show_pods $pods
}
show_pods() {
  note "What's running:"
  for p in "$@"; do
    kubectl -n "$NS" get pod "$p" -o jsonpath='  {.metadata.name}: {.metadata.annotations.what}{"\n"}    requests {.spec.containers[0].resources.requests}   limits {.spec.containers[0].resources.limits}{"\n"}'
  done
}

# CPU used by a pod, in millicores, over about N seconds (default 5).
# The clock and cpu.stat are read together on the node, so slow kubectl calls don't skew it.
pod_millicores() {
  local dir; dir="$(pod_cgroup_dir "$1")"
  local a b; a=$(on_node "echo \$(date +%s%N) \$(awk '/^usage_usec/{print \$2}' $dir/cpu.stat)")
  sleep "${2:-5}"
  b=$(on_node "echo \$(date +%s%N) \$(awk '/^usage_usec/{print \$2}' $dir/cpu.stat)")
  set -- $a $b
  echo $(( ($4 - $2) * 1000000 / ($3 - $1) ))
}

# --- Pacing for the incidents ---
# A numbered section header, and a pause that waits for Enter (skipped when there's no keyboard, as in CI).
stage() { printf '\n%s── %s ──%s\n\n' "$BOLD" "$*" "$RESET"; }
pause() { if [ -t 0 ] && [ -t 1 ]; then read -rp "  ⏎  Press Enter to continue " _; fi; }
wait_ready() { kubectl -n "$NS" wait --for=condition=Ready "pod/$1" --timeout=120s >/dev/null; }
