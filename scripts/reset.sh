#!/usr/bin/env bash
# make reset: remove everything the labs created, keep the cluster.
set -uo pipefail
C="${CLUSTER:-under-the-hood}"; W="$C-worker"
echo "Removing Docker containers from labs 01–07 (lab-*)..."
docker ps -a --format '{{.Names}}' | grep -E '^lab-' | xargs -r docker rm -f
if kind get clusters 2>/dev/null | grep -qx "$C"; then
  echo "Removing hand-made cgroups on the worker..."
  docker exec "$W" sh -c 'for d in /sys/fs/cgroup/lab-*; do [ -d "$d" ] || continue; for p in $(cat $d/cgroup.procs); do kill -9 $p; done; sleep 1; rmdir $d && echo "  removed $d"; done' 2>/dev/null
  echo "Deleting lab namespaces and priority classes..."
  kubectl --context "kind-$C" delete ns lab lab-checkpoints lab-quota lab-limits --ignore-not-found --wait=true
  kubectl --context "kind-$C" delete priorityclass lab-low lab-high --ignore-not-found
  kubectl --context "kind-$C" create ns lab >/dev/null
  echo "Clean. kubectl still uses namespace lab."
fi
