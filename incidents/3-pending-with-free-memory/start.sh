#!/usr/bin/env bash
# Incident 3: a new pod won't start, even though the node's memory is almost empty.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$NS" wait --for=delete pod -l incident --timeout=60s >/dev/null 2>&1 || true

title "Incident 3: Pending, with memory to spare"
# Each batch pod reserves a third of the node's allocatable memory, minus a little.
alloc_mi=$(( $(kubectl get node "$WORKER" -o jsonpath='{.status.allocatable.memory}' | tr -d 'Ki') / 1024 ))
mem="$(( (alloc_mi - 800) / 3 ))Mi"
ensure_ns
step "kubectl -n $NS apply -f pods.yaml   (3 batch jobs, then new-feature)"
sed "s/__MEM__/$mem/" "$(dirname "$0")/pods.yaml" | kubectl -n "$NS" apply -f -
show_pods batch-1 batch-2 batch-3 new-feature
sleep 8

step "kubectl -n $NS get pods -l incident"
kubectl -n "$NS" get pods -l incident | sed 's/^/  /'
used=$(( $(on_node "cat $(kubepods_root)/memory.current") / 1048576 ))
echo
echo "  Memory actually in use by all pods on the node: ${used} MiB of ${alloc_mi} MiB"

cat <<'MSG'

  THE TICKET
  "new-feature has been Pending for ages. The node is using a fraction of its memory.
   Is the scheduler broken?"

  YOUR JOB: find out why new-feature can't be placed.

  Things to try:
    kubectl -n lab describe pod new-feature | tail -5
    kubectl describe node under-the-hood-worker | grep -A6 "Allocated resources"
    kubectl -n lab get pods -l incident -o custom-columns=NAME:.metadata.name,MEM_REQUEST:.spec.containers[0].resources.requests.memory

  When you know:  make answer-3 CAUSE=<one or two words>
  Stuck?          make hint-3
MSG
