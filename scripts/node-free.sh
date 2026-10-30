#!/usr/bin/env bash
# Print how much of the worker's CPU (millicores) or memory (Mi) is not yet requested by any pod.
# Usage: ./scripts/node-free.sh cpu|memory
set -euo pipefail
w="${CLUSTER:-under-the-hood}-worker"
case "${1:?usage: $0 cpu|memory}" in
  cpu)    path='{.status.allocatable.cpu}';    field='{.resources.requests.cpu}';    conv='/m$/{sub(/m$/,"");s+=$1;next} /^[0-9.]+$/{s+=$1*1000}' ;;
  memory) path='{.status.allocatable.memory}'; field='{.resources.requests.memory}'; conv='/Ki$/{sub(/Ki$/,"");s+=$1/1024;next} /Mi$/{sub(/Mi$/,"");s+=$1;next} /Gi$/{sub(/Gi$/,"");s+=$1*1024;next} /^[0-9]+$/{s+=$1/1048576}' ;;
  *) echo "usage: $0 cpu|memory"; exit 1 ;;
esac
alloc=$(kubectl get node "$w" -o jsonpath="$path" | awk "$conv END{print int(s)}")
used=$(kubectl get pods -A --field-selector "spec.nodeName=$w,status.phase!=Succeeded,status.phase!=Failed" \
  -o jsonpath="{range .items[*]}{range .spec.containers[*]}$field{\"\\n\"}{end}{end}" | awk "$conv END{print int(s)}")
echo $(( alloc - used ))
