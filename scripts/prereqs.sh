#!/usr/bin/env bash
set -uo pipefail
missing=0
for tool in docker kind kubectl; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'ok       %s\n' "$tool"
  else
    printf 'missing  %s\n' "$tool"; missing=1
  fi
done
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running. Start Docker Desktop and try again."; missing=1
fi
if [ "$missing" -ne 0 ]; then
  echo ""
  echo "Install guide: see 'Setup' in README.md (macOS: brew install kind kubectl; Windows: run inside WSL2)."
  exit 1
fi
