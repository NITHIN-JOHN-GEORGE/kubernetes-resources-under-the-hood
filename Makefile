# kubernetes-resources-under-the-hood
# Run `make help` to see every target.

SHELL := /usr/bin/env bash
CLUSTER ?= under-the-hood
export CLUSTER

MODULES := 00-setup 01-requests-and-limits 02-cpu-throttling 03-cpu-weight 04-memory-and-oom 05-qos-classes

.PHONY: help prereqs cluster delete-cluster all check-all clean $(MODULES)

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

clean: ## Delete the lab namespace and everything in it
	@kubectl delete ns lab --ignore-not-found
