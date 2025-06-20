# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 0.1.0

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# kafka.w6d.io/kafka-bundle:$VERSION and kafka.w6d.io/kafka-catalog:$VERSION.
IMAGE_TAG_BASE ?= kafka.w6d.io/kafka

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v$(VERSION)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.39.2
# Image URL to use all building/pushing image targets
IMG ?= ghcr.io/w6d-io/kafka:$(VERSION)
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.31.0

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

ifeq (,$(OS))
OS=$(shell go env GOOS)
endif

ifeq (,$(ARCH))
ARCH=$(shell go env GOARCH)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=kafka-operator-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test $$(go list ./... | grep -v /e2e) -coverprofile cover.out

# Utilize Kind or modify the e2e tests to load the image locally, enabling compatibility with other vendors.
.PHONY: test-e2e  # Run the e2e tests against a Kind k8s instance that is spun up.
test-e2e:
	go test ./test/e2e/ -v -ginkgo.v

.PHONY: lint
lint: golangci-lint ## Run golangci-lint linter
	$(GOLANGCI_LINT) run

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint linter and perform fixes
	$(GOLANGCI_LINT) run --fix

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/kafka-controller cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go ${ARGS}

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build --build-arg=VERSION=${VERSION} -t ${IMG}  .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - be able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- $(CONTAINER_TOOL) buildx create --name kafka-builder
	$(CONTAINER_TOOL) buildx use kafka-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) --tag ${IMG} -f Dockerfile.cross .
	- $(CONTAINER_TOOL) buildx rm kafka-builder
	rm Dockerfile.cross

.PHONY: build-installer
build-installer: manifests generate kustomize ## Generate a consolidated YAML with CRDs and deployment.
	mkdir -p dist
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default > dist/install.yaml

##@ Security

.PHONY: security-scan-all
security-scan-all: chart-security-scan govulncheck gosec ## Run all security scans
	@echo "All security scans completed"

.PHONY: govulncheck
govulncheck: ## Run Go vulnerability check
	@if ! command -v govulncheck >/dev/null 2>&1; then \
		echo "Installing govulncheck..."; \
		go install golang.org/x/vuln/cmd/govulncheck@latest; \
	fi
	govulncheck ./...

.PHONY: gosec
gosec: ## Run gosec security scanner
	@if ! command -v gosec >/dev/null 2>&1; then \
		echo "Installing gosec..."; \
		go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest; \
	fi
	gosec ./...

.PHONY: gosec-sarif
gosec-sarif: ## Run gosec and output SARIF
	@if ! command -v gosec >/dev/null 2>&1; then \
		echo "Installing gosec..."; \
		go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest; \
	fi
	@mkdir -p dist
	gosec -fmt sarif -out dist/gosec-results.sarif ./...

.PHONY: hadolint
hadolint: ## Run Dockerfile linter
	@if ! command -v hadolint >/dev/null 2>&1; then \
		echo "Installing hadolint..."; \
		OS=$(uname -s | tr '[:upper:]' '[:lower:]') && \
		ARCH=$(uname -m | sed 's/x86_64/x86_64/') && \
		curl -sL "https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-${OS}-${ARCH}" -o $(LOCALBIN)/hadolint && \
		chmod +x $(LOCALBIN)/hadolint; \
	fi
	$(LOCALBIN)/hadolint Dockerfile

.PHONY: security-install-tools
security-install-tools: checkov ## Install all security tools
	@echo "Installing security tools..."
	go install golang.org/x/vuln/cmd/govulncheck@latest
	go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest
	@echo "Security tools installed"

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: kustomize ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

##@ Helm Charts

# Chart configuration
CHART_NAME ?= kafka-operator
CHART_DIR ?= charts/$(CHART_NAME)
CHARTS_DIR ?= charts
CHART_VERSION ?= $(VERSION)

##@ Chart CI/CD Integration

.PHONY: ci-chart-test
ci-chart-test: chart-sync-crds chart-lint ## Run chart tests for CI
	@echo "Running chart tests for CI..."
	$(CT) lint --config .github/ct.yaml
	$(CT) install --config .github/ct.yaml

.PHONY: ci-chart-release
ci-chart-release: chart-sync-crds chart-update-version chart-package ## Prepare chart for release in CI
	@echo "Chart prepared for release"

.PHONY: chart-verify
chart-verify: helm chart-sync-crds ## Verify chart integrity
	$(HELM) lint $(CHART_DIR)
	$(HELM) template test $(CHART_DIR) --validate > /dev/null
	@echo "Chart verification passed"

.PHONY: chart-security-scan
chart-security-scan: helm ## Scan chart for security issues
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -f $(CHART_DIR) --framework helm; \
	else \
		echo "Checkov not installed, skipping security scan"; \
		echo "Install with: pip install checkov"; \
	fi

.PHONY: chart-sync-crds
chart-sync-crds: manifests ## Sync CRDs to Helm chart
	@mkdir -p $(CHART_DIR)/crds
	cp config/crd/bases/*.yaml $(CHART_DIR)/crds/
	@echo "CRDs synced to $(CHART_DIR)/crds/"

.PHONY: chart-update-version
chart-update-version: yq ## Update chart version and appVersion
	file $(YQ)
	cat $(YQ)
	$(YQ) eval '.version = "$(CHART_VERSION)"' -i $(CHART_DIR)/Chart.yaml
	$(YQ) eval '.appVersion = "$(VERSION)"' -i $(CHART_DIR)/Chart.yaml
	@echo "Chart version updated to $(CHART_VERSION), appVersion updated to $(VERSION)"

.PHONY: chart-deps
chart-deps: helm ## Update chart dependencies
	$(HELM) dependency update $(CHART_DIR)

.PHONY: chart-lint
chart-lint: helm chart-sync-crds ## Lint Helm chart
	$(HELM) lint $(CHART_DIR)

.PHONY: chart-test
chart-test: ct kind-cluster ## Test Helm chart with chart-testing
	$(CT) lint --config .github/ct.yaml --charts $(CHART_DIR)
	$(CT) install --config .github/ct.yaml --charts $(CHART_DIR)

.PHONY: chart-test-local
chart-test-local: helm chart-sync-crds ## Test chart installation locally
	$(HELM) template test $(CHART_DIR) --debug > /tmp/kafka-operator-template.yaml
	@echo "Chart template rendered to /tmp/kafka-operator-template.yaml"
	$(HELM) install kafka-operator-test $(CHART_DIR) --dry-run --debug

.PHONY: chart-package
chart-package: helm chart-sync-crds chart-update-version ## Package Helm chart
	@mkdir -p dist/charts
	$(HELM) package $(CHART_DIR) --destination dist/charts
	@echo "Chart packaged in dist/charts/"

.PHONY: chart-release
chart-release: cr chart-package ## Release Helm chart using chart-releaser
	$(CR) upload --config .github/cr.yaml
	$(CR) index --config .github/cr.yaml

.PHONY: chart-docs
chart-docs: helm-docs ## Generate chart documentation
	$(HELM_DOCS) --chart-search-root=$(CHARTS_DIR)

.PHONY: chart-install
chart-install: helm chart-sync-crds ## Install chart to current k8s cluster
	$(HELM) upgrade --install kafka-operator $(CHART_DIR) \
		--set image.tag=$(VERSION) \
		--create-namespace \
		--namespace kafka-operator-system

.PHONY: chart-uninstall
chart-uninstall: helm ## Uninstall chart from current k8s cluster
	$(HELM) uninstall kafka-operator --namespace kafka-operator-system

.PHONY: chart-debug
chart-debug: helm chart-sync-crds ## Debug chart rendering
	$(HELM) template kafka-operator $(CHART_DIR) \
		--set image.tag=$(VERSION) \
		--debug

##@ Testing Infrastructure

.PHONY: kind-cluster
kind-cluster: kind ## Create kind cluster for testing
	@if ! $(KIND) get clusters | grep -q "chart-testing"; then \
		echo "Creating kind cluster for chart testing..."; \
		$(KIND) create cluster --name chart-testing --config .github/kind-config.yaml; \
	else \
		echo "Kind cluster 'chart-testing' already exists"; \
	fi

.PHONY: kind-cluster-delete
kind-cluster-delete: kind ## Delete kind cluster
	$(KIND) delete cluster --name chart-testing

.PHONY: kind-load-image
kind-load-image: kind docker-build ## Load docker image into kind cluster
	$(KIND) load docker-image $(IMG) --name chart-testing

##@ Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUBECTL ?= kubectl
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest
GOLANGCI_LINT = $(LOCALBIN)/golangci-lint
HELM ?= $(LOCALBIN)/helm
CT ?= $(LOCALBIN)/ct
CR ?= $(LOCALBIN)/cr
KIND ?= $(LOCALBIN)/kind
YQ ?= $(LOCALBIN)/yq
HELM_DOCS ?= $(LOCALBIN)/helm-docs

## Tool Versions
KUSTOMIZE_VERSION ?= v5.4.3
CONTROLLER_TOOLS_VERSION ?= v0.16.1
ENVTEST_VERSION ?= release-0.19
GOLANGCI_LINT_VERSION ?= v1.59.1
HELM_VERSION ?= v3.15.2
CT_VERSION ?= v3.11.0
CR_VERSION ?= v1.6.1
KIND_VERSION ?= v0.32.0
YQ_VERSION ?= v4.45.4
HELM_DOCS_VERSION ?= v1.14.2

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) GO111MODULE=on go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download setup-envtest locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

.PHONY: golangci-lint
golangci-lint: $(GOLANGCI_LINT) ## Download golangci-lint locally if necessary.
$(GOLANGCI_LINT): $(LOCALBIN)
	test -s $(LOCALBIN)/golangci-lint || GOBIN=$(LOCALBIN) go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)

.PHONY: helm
helm: $(HELM) ## Download helm locally if necessary.
$(HELM): $(LOCALBIN)
	@{ \
	set -e ;\
	mkdir -p $(dir $(HELM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSL https://get.helm.sh/helm-$(HELM_VERSION)-$${OS}-$${ARCH}.tar.gz | tar -xzC $(LOCALBIN) --strip-components=1 $${OS}-$${ARCH}/helm ;\
	chmod +x $(HELM) ;\
	}

.PHONY: ct
ct: $(CT) ## Download chart-testing locally if necessary.
$(CT): $(LOCALBIN)
	@{ \
	set -e ;\
	mkdir -p $(dir $(CT)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSL https://github.com/helm/chart-testing/releases/download/$(CT_VERSION)/chart-testing_$(CT_VERSION:v%=%)_$${OS}_$${ARCH}.tar.gz | tar -xzC $(LOCALBIN) ct ;\
	chmod +x $(CT) ;\
	}

.PHONY: cr
cr: $(CR) ## Download chart-releaser locally if necessary.
$(CR): $(LOCALBIN)
	@{ \
	set -e ;\
	mkdir -p $(dir $(CR)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSL https://github.com/helm/chart-releaser/releases/download/$(CR_VERSION)/chart-releaser_$(CR_VERSION:v%=%)_${OS}_${ARCH}.tar.gz | tar -xzC $(LOCALBIN) cr ;\
	chmod +x $(CR) ;\
	}

.PHONY: kind
kind: $(KIND) ## Download kind locally if necessary.
$(KIND): $(LOCALBIN)
	@{ \
	set -e ;\
	mkdir -p $(dir $(KIND)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSL https://github.com/kubernetes-sigs/kind/releases/download/$(KIND_VERSION)/kind-${OS}-${ARCH} -o $(KIND) ;\
	chmod +x $(KIND) ;\
	}

.PHONY: yq
yq: $(YQ) ## Download yq locally if necessary.
$(YQ): $(LOCALBIN)
	@{ \
	set -e ;\
	mkdir -p $(dir $(YQ)) ;\
	echo "https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)" && \
	curl -sSL "https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)" -o $(YQ) ;\
	chmod +x $(YQ) ;\
	}

.PHONY: helm-docs
helm-docs: $(HELM_DOCS) ## Download helm-docs locally if necessary.
$(HELM_DOCS): $(LOCALBIN)
	@{ \
	set -e ;\
	mkdir -p $(dir $(HELM_DOCS)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSL https://github.com/norwoodj/helm-docs/releases/download/$(HELM_DOCS_VERSION)/helm-docs_$(HELM_DOCS_VERSION:v%=%)_${OS}_${ARCH}.tar.gz | tar -xzC $(LOCALBIN) helm-docs ;\
	chmod +x $(HELM_DOCS) ;\
	}


.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_${OS}_${ARCH} ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

.PHONY: opm
OPM = $(LOCALBIN)/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.23.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)