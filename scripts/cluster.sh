#!/usr/bin/env bash
# make cluster PROFILE=<name>: create the kind cluster from kind/<name>.yaml, load lab-tools,
# create the "lab" namespace and make it the default for kubectl.
set -euo pipefail
profile="${1:-default}"; image="${2:-lab-tools:1.0}"; cluster="${CLUSTER:-under-the-hood}"
config="kind/${profile}.yaml"
[ -f "$config" ] || { echo "No profile '$profile'. Choose one of: $(ls kind | sed 's/.yaml//' | tr '\n' ' ')"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$cluster"; then
  current="$(kubectl --context "kind-$cluster" get node "$cluster-worker" -o jsonpath='{.metadata.labels.lab-profile}' 2>/dev/null || true)"
  if [ "$current" != "$profile" ]; then
    echo "The cluster already exists with profile '${current:-unknown}'. A profile can't be changed on a running cluster."
    echo "Run: make clean && make cluster PROFILE=$profile"
    exit 1
  fi
  echo "Cluster $cluster already exists (profile $profile)."
else
  kind create cluster --config "$config"
fi
kubectl config use-context "kind-$cluster" >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=180s
kind load docker-image "$image" --name "$cluster" --nodes "$cluster-worker"
kubectl get ns lab >/dev/null 2>&1 || kubectl create ns lab
kubectl config set-context --current --namespace=lab >/dev/null
echo "Ready: profile $profile, image $image loaded, kubectl now uses namespace lab."
