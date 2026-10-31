#!/usr/bin/env bash
# Incident 3: a new pod won't start, even though the node's memory is almost empty.
source "$(dirname "$0")/../../lib/common.sh"
kubectl -n "$NS" delete pod -l incident --ignore-not-found --wait=true >/dev/null 2>&1
title "Incident 3: Pending, with memory to spare"

stage "1. The scene"
# Each batch job reserves about a third of the node's allocatable memory.
alloc_mi=$(( $(kubectl get node "$WORKER" -o jsonpath='{.status.allocatable.memory}' | tr -d 'Ki') / 1024 ))
mem="$(( (alloc_mi - 800) / 3 ))Mi"
ensure_ns
step "kubectl apply -f pods.yaml   (3 nightly batch jobs, then new-feature)"
sed "s/__MEM__/$mem/" "$(dirname "$0")/pods.yaml" | kubectl -n "$NS" apply -f -
show_pods batch-1 batch-2 batch-3 new-feature
pause

stage "2. What the on-call engineer sees"
sleep 3
run kubectl -n "$NS" get pods -l incident
used=$(( $(on_node "cat $(kubepods_root)/memory.current") / 1048576 ))
echo
echo "  The node's memory graph: ${used} MiB in use by all pods, out of ${alloc_mi} MiB."
note "  Almost empty, and new-feature is still Pending."
pause

stage "3. The ticket"
cat <<'MSG'
  "new-feature has been Pending for ages. The node is using a fraction of its memory.
   Is the scheduler broken?"

  YOUR TURN. Find out why new-feature can't be placed. Look at these, in order:

    1. What the scheduler said. Read the Events at the bottom.
         kubectl describe pod new-feature | tail -5

    2. What the node has promised, as opposed to what it uses.
         kubectl describe node under-the-hood-worker | grep -A6 "Allocated resources"

    3. Who the promises went to.
         kubectl get pods -l incident -o custom-columns=NAME:.metadata.name,MEM_REQUEST:.spec.containers[0].resources.requests.memory

  A clue, one at a time:   make hint-3
  When you know:           make answer-3 CAUSE=<one or two words>
MSG
