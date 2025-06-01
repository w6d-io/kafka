# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kubernetes operator for managing Kafka topics using the Kubebuilder framework. The operator provides a Custom Resource Definition (CRD) called `KafkaTopic` that allows users to declaratively manage Kafka topics in their clusters.

## Development Commands

### Building and Testing
- `make build` - Build the controller binary to `bin/kafka-controller`
- `make test` - Run unit tests with coverage
- `make test-e2e` - Run end-to-end tests against a Kind cluster
- `make lint` - Run golangci-lint linter
- `make lint-fix` - Run linter with automatic fixes
- `make fmt` - Format Go code
- `make vet` - Run Go vet

### Code Generation
- `make manifests` - Generate CRDs, RBAC, and webhook configurations
- `make generate` - Generate DeepCopy methods and other boilerplate code

### Local Development
- `make run` - Run the controller locally against configured Kubernetes cluster
- `make install` - Install CRDs into the cluster
- `make uninstall` - Remove CRDs from the cluster

### Docker Operations
- `make docker-build IMG=<registry>/kafka:tag` - Build Docker image
- `make docker-push IMG=<registry>/kafka:tag` - Push Docker image

### Deployment
- `make deploy IMG=<registry>/kafka:tag` - Deploy controller to cluster
- `make undeploy` - Remove controller from cluster
- `kubectl apply -k config/samples/` - Apply sample KafkaTopic resources

## Architecture

### Core Components

**API Layer** (`api/v1alpha1/`):
- `KafkaTopic` CRD defines the schema for managing Kafka topics
- Key fields: `BoostrapServer` (Kafka connection), `Topics` (array of topic configurations)
- Status tracking with `State` (Failed/Succeeded) and `Conditions`

**Controller Layer** (`internal/controller/`):
- `KafkaTopicReconciler` implements the core reconciliation logic
- Connects to Kafka using `segmentio/kafka-go` client
- Creates topics if they don't exist, skips existing ones
- Handles connection failures and updates resource status

**Kafka Client** (`internal/pkg/k/`):
- Abstracts Kafka operations for connection management and topic verification
- Used by the controller for actual Kafka interactions

**Types** (`internal/types/`):
- Shared type definitions for topic configuration

### Key Dependencies
- Uses `controller-runtime` for Kubernetes controller framework
- `segmentio/kafka-go` for Kafka client operations
- `w6d-io/x` for logging utilities with correlation ID support

### Project Structure
- `cmd/main.go` - Main entry point with manager setup
- `config/` - Kubernetes manifests and Kustomize configurations
- `test/` - Unit and e2e test suites
- Uses standard Kubebuilder project layout and conventions