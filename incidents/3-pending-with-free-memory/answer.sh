#!/usr/bin/env bash
# Check an answer for incident 3 and explain what was going on, one step at a time.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *request*|*reserv*|*allocat*|*promis*) pass "Correct: the idle pods' memory requests." ;;
  "") echo "Usage: make answer-3 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-3"; exit 1 ;;
esac
kubectl -n "$NS" get pod new-feature >/dev/null 2>&1 || { echo "new-feature isn't there. Start it with: make incident-3"; exit 1; }

stage "1. The evidence"
note "  What the scheduler said about new-feature:"
kubectl -n "$NS" get events --field-selector involvedObject.name=new-feature,reason=FailedScheduling -o jsonpath='{.items[-1:].message}{"\n"}' | sed 's/^/    /'
echo
note "  What the node has promised (requests), not what it uses:"
kubectl describe node "$WORKER" | grep -A6 "Allocated resources" | sed 's/^/    /'
pause

stage "2. Why it happened"
cat <<'MSG'
  1. The scheduler fits pods by comparing their REQUESTS with the node's allocatable memory.
     It never looks at real usage.
  2. The three batch jobs each requested about a third of the node, so nearly all of it was
     promised away, even though they were only sleeping.
  3. new-feature asked for 1 GiB, and there wasn't 1 GiB left to promise.
     "Insufficient memory" means "not enough left to promise", not "not enough free".
MSG
pause

stage "3. The fix, live"
note "  Set requests close to what pods really use (their working set), and let idle jobs ask for less."
note "  Here we just remove one batch job and watch new-feature get placed:"
run kubectl -n "$NS" delete pod batch-3 --wait=true
kubectl -n "$NS" wait --for=condition=Ready pod/new-feature --timeout=60s >/dev/null 2>&1
kubectl -n "$NS" get pod new-feature | sed 's/^/  /'
pause

stage "4. Remember"
cat <<'MSG'
  Scheduling runs on requests, not usage. Oversized requests waste a node even when it's idle.

  Revisit: labs/09-four-checkpoints and labs/18-node-pressure-eviction.   Clean up: make reset
MSG
