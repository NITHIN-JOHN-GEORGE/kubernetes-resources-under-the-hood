# kubernetes-resources-under-the-hood
# make is only for the environment and for checks. The lessons use kubectl, docker and cat.
# Run `make help` to see every target.

SHELL   := /usr/bin/env bash
CLUSTER ?= under-the-hood
PROFILE ?= default
IMAGE   := lab-tools:1.0
export CLUSTER

.PHONY: help image cluster check-setup check test reset clean

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Labs live in labs/. Open a lab's README.md and follow it with kubectl, docker and cat."

image: ## Build the lab-tools image (burn, alloc, cache, forkmany, serve, load)
	docker build -t $(IMAGE) image/

cluster: image ## Create the cluster and load lab-tools (PROFILE=default|pressure|pids)
	@./scripts/cluster.sh $(PROFILE) $(IMAGE)

check-setup: ## Check Docker, tools, cluster, cgroups v2, and look for leftovers
	@./scripts/check-setup.sh

check: ## Read-only PASS/FAIL on a lab you just did: make check LAB=14
	@if [ -z "$(LAB)" ]; then echo "Usage: make check LAB=14"; exit 1; fi
	@./labs/$(LAB)-*/check.sh

test: ## Run labs end to end and save expected.txt (LAB=14 for one, or all for the profile)
	@./scripts/run-lab.sh $(or $(LAB),all)

incident-%: ## Start an incident: make incident-1
	@rm -f $${TMPDIR:-/tmp}/k8s-under-the-hood-hint-$*
	@./incidents/$*-*/start.sh

hint-%: ## The next clue for an incident, one at a time: make hint-1
	@./scripts/hint.sh $*

answer-%: ## Check your answer: make answer-1 CAUSE=<answer> (CAUSE=show to see it)
	@./incidents/$*-*/answer.sh "$(CAUSE)"

reset: ## Remove everything the labs created, keep the cluster
	@./scripts/reset.sh

clean: ## Delete the cluster
	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER)"; then kind delete cluster --name $(CLUSTER); \
	else echo "No kind cluster named $(CLUSTER), nothing to delete."; fi
