#!/usr/bin/env bash
# Print the folder of a pod's cgroup on the worker node.
# Usage: ./scripts/pod-cgroup.sh <pod> [namespace]
# Example: docker exec under-the-hood-worker cat "$(./scripts/pod-cgroup.sh requests-limits)/cpu.max"
set -euo pipefail
pod="${1:?usage: $0 <pod> [namespace]}"; ns="${2:-lab}"
uid="$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.uid}' | tr '-' '_')"
docker exec under-the-hood-worker sh -c "find /sys/fs/cgroup -type d -name '*pod${uid}.slice' | head -n1"
