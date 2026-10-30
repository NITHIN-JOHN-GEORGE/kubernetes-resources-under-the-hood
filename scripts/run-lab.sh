#!/usr/bin/env bash
# make test LAB=14 (or make test for every lab that fits the current cluster profile).
# Runs a lab exactly as a reader would: every ```bash block in its README, in order.
# Everything is shown as it runs and saved to the lab's expected.txt, then check.sh grades it, then the
# "Clean up" blocks run. Blocks marked ```sh or ```text are never run.
set -uo pipefail
cd "$(dirname "$0")/.."
C="${CLUSTER:-under-the-hood}"
want="${1:-all}"

profile_now() { kubectl --context "kind-$C" get node "$C-worker" -o jsonpath='{.metadata.labels.lab-profile}' 2>/dev/null; }

run_one() {
  local dir="$1" name; name="$(basename "$dir")"
  local readme="$dir/README.md" out="$dir/expected.txt" tmp; tmp="$(mktemp -d)"
  local need; need="$(grep -m1 'Runs on:' "$readme" | grep -o 'PROFILE=[a-z]*' | cut -d= -f2)"
  local docker_only=0; grep -qm1 'Runs on:\*\* Docker only' "$readme" && docker_only=1
  if [ "$docker_only" = 1 ] && [ "$want" = all ] && [ -n "$(profile_now)" ] && [ "$(profile_now)" != default ]; then
    echo "SKIP $name: Docker-only labs run with the default profile"; return 2
  fi
  if [ "$docker_only" = 0 ]; then
    local have; have="$(profile_now)"
    if [ -z "$have" ]; then echo "SKIP $name: no cluster (make cluster)"; return 2; fi
    if [ "${need:-default}" != "$have" ]; then echo "SKIP $name: needs PROFILE=${need:-default}, cluster has $have"; return 2; fi
  fi
  # Split the README's bash blocks into main steps and clean-up steps.
  awk -v d="$tmp" '
    /^## Clean up/ {clean=1}
    /^```bash[[:space:]]*$/ {inb=1; f=sprintf("%s/%s.sh", d, clean?"clean":"main"); next}
    /^```/ && inb {inb=0; next}
    inb {print > f}
  ' "$readme"
  echo "== $name"
  : > "$out"
  # One shell for all the steps, so variables like CID=... carry over, as in a terminal.
  # Show each command and its output as it runs (bash -v echoes every line before running it),
  # and save the same text to expected.txt.
  [ -e "$tmp/main.sh" ] && bash -v "$tmp/main.sh" 2>&1 | tee -a "$out"
  echo
  echo "-- checks"
  local rc=0
  "$dir/check.sh" | tee -a "$out" || rc=1
  echo "-- cleaning up"
  [ -e "$tmp/clean.sh" ] && bash "$tmp/clean.sh" > /dev/null 2>&1
  rm -rf "$tmp"
  return $rc
}

if [ "$want" = all ]; then
  passed=0; failed=0; skipped=0; failures=""
  for dir in $(ls -d labs/*/ | sort -V); do
    run_one "${dir%/}"; rc=$?
    case $rc in 0) passed=$((passed+1));; 2) skipped=$((skipped+1));; *) failed=$((failed+1)); failures="$failures $(basename "$dir")";; esac
  done
  echo; echo "passed $passed, failed $failed, skipped $skipped${failures:+ (failed:$failures)}"
  [ "$failed" = 0 ]
else
  dir="$(ls -d labs/${want}-* 2>/dev/null | head -1)"
  [ -n "$dir" ] || { echo "No lab $want in labs/"; exit 1; }
  run_one "$dir"; rc=$?; [ $rc = 2 ] && exit 0; exit $rc
fi
