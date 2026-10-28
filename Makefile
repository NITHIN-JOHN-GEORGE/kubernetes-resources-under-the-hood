# kubernetes-resources-under-the-hood
# Run `make help` to see every target.

SHELL := /usr/bin/env bash
CLUSTER ?= under-the-hood
export CLUSTER

# Every folder under modules/ is a module, in numeric order.
MODULES := $(sort $(notdir $(wildcard modules/*)))

.PHONY: help prereqs cluster delete-cluster all check-all clean reset restore-kubelet $(MODULES)

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Modules: make <module>, for example: make 02-cpu-throttling"
	@for m in $(MODULES); do echo "    $$m"; done

prereqs: ## Check that docker, kind and kubectl are installed
	@./scripts/prereqs.sh

cluster: prereqs ## Create the 2-node kind cluster
	@kind get clusters 2>/dev/null | grep -qx "$(CLUSTER)" || kind create cluster --config kind-config.yaml
	@kubectl config use-context kind-$(CLUSTER) >/dev/null
	@kubectl wait --for=condition=Ready node --all --timeout=180s

delete-cluster: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

$(MODULES): ## Run a module (demo + checks)
	@./modules/$@/run.sh

all: $(MODULES) ## Run every module in order

check-all: ## Run every module and fail on the first failed check (used by CI)
	@set -e; for m in $(MODULES); do ./modules/$$m/run.sh; done

clean: ## Delete the whole kind cluster and everything in it (start again with make cluster)
	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER)"; then \
		kind delete cluster --name $(CLUSTER); \
	else \
		echo "No kind cluster named $(CLUSTER), nothing to delete."; \
	fi

reset: ## Keep the cluster, but remove everything the lab created and undo any kubelet change
	@echo "Restoring the worker's kubelet config if a module left it changed..."
	@docker exec $(CLUSTER)-worker sh -c 'if [ -f /var/lib/kubelet/config.yaml.lab-backup ]; then mv /var/lib/kubelet/config.yaml.lab-backup /var/lib/kubelet/config.yaml && systemctl restart kubelet && echo "  restored"; else echo "  nothing to restore"; fi'
	@echo "Deleting lab namespaces and priority classes..."
	@kubectl delete ns lab lab-quota lab-limits --ignore-not-found --wait=true
	@kubectl delete priorityclass lab-low lab-high --ignore-not-found
	@kubectl wait --for=condition=Ready node --all --timeout=180s >/dev/null && echo "Cluster is clean."

restore-kubelet: ## Only put back the worker's original kubelet config
	@docker exec $(CLUSTER)-worker sh -c 'if [ -f /var/lib/kubelet/config.yaml.lab-backup ]; then mv /var/lib/kubelet/config.yaml.lab-backup /var/lib/kubelet/config.yaml && systemctl restart kubelet && echo restored; else echo "nothing to restore"; fi'
