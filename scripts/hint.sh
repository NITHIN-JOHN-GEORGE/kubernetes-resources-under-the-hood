#!/usr/bin/env bash
# make hint-N: show the next clue for incident N, one at a time.
# Clues are the "## Clue" sections of incidents/N-*/hint.md. Progress is kept in /tmp.
set -u
n="${1:?usage: $0 <incident number>}"
file="$(ls incidents/${n}-*/hint.md 2>/dev/null | head -1)"
[ -n "$file" ] || { echo "No incident $n"; exit 1; }
state="${TMPDIR:-/tmp}/k8s-under-the-hood-hint-$n"
seen=$(cat "$state" 2>/dev/null || echo 0)
total=$(grep -c '^## Clue' "$file")
next=$(( seen + 1 ))
if [ "$next" -gt "$total" ]; then
  echo "That was the last clue. When you're ready: make answer-$n CAUSE=<your answer>   (or CAUSE=show)"
  echo "(Start the clues again with: rm $state)"
  exit 0
fi
echo
awk -v k="$next" '/^## Clue/{c++} c==k' "$file"
echo
echo "$next" > "$state"
[ "$next" -lt "$total" ] && echo "  ($next of $total. Run make hint-$n again for the next clue.)" || echo "  (That's the last clue.)"
