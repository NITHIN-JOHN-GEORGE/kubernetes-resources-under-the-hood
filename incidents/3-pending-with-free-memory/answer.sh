#!/usr/bin/env bash
# Check an answer for incident 3 and explain what was going on.
source "$(dirname "$0")/../../lib/common.sh"
guess="$(echo "${1:-}" | tr 'A-Z' 'a-z')"
case "$guess" in
  *request*|*reserv*|*allocat*) pass "Correct: the idle pods' memory requests." ;;
  "") echo "Usage: make answer-3 CAUSE=<your answer>   (or CAUSE=show to see the answer)"; exit 1 ;;
  show) note "Here's the answer." ;;
  *) fail "Not quite. Try: make hint-3"; exit 1 ;;
esac

title "What was happening"
step "kubectl describe node $WORKER | grep -A6 'Allocated resources'"
kubectl describe node "$WORKER" | grep -A6 "Allocated resources" | sed 's/^/  /'
cat <<'MSG'

  The scheduler only compares requests with the node's allocatable memory. It never looks at
  real usage. The three batch jobs each requested about a third of the node, so almost all of
  it was promised away, even though they were only sleeping. new-feature asked for 1 GiB and
  there was no unpromised 1 GiB left. "Insufficient memory" means "not enough left to promise".

  The fix: set requests close to what pods really use (the working set, chapter 9), and
  let idle jobs ask for less. Watch: delete one batch job and new-feature gets scheduled.
MSG
run kubectl -n "$NS" delete pod batch-3 --wait=true
kubectl -n "$NS" wait --for=condition=Ready pod/new-feature --timeout=60s >/dev/null 2>&1 || true
kubectl -n "$NS" get pod new-feature | sed 's/^/  /'
note "  Clean up with: make incident-clean"
