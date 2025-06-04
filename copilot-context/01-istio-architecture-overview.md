# Istio Architecture Overview

## Introduction

Istio is a service mesh that provides a uniform way to connect, secure, control, and observe microservices. This document provides a high-level overview of Istio's architecture and components to help newcomers navigate the codebase.

## Core Components

Istio consists of several key components:

### 1. Control Plane

**Istiod** is the centralized control plane component that provides:
- Service discovery
- Configuration management
- Certificate management
- Sidecar proxy configuration

In the codebase, Istiod is primarily implemented in the `pilot/` directory, which contains the core logic for the control plane.

### 2. Data Plane

**Envoy Proxy** is the data plane component that:
- Routes traffic between services
- Enforces policies
- Gathers telemetry data

There are two main deployment models for the data plane:
- **Sidecar model**: Each service instance has a companion Envoy proxy (in `pkg/envoy/` and related directories)
- **Ambient mesh**: A sidecarless approach that moves proxy functionality out of application pods (see the newer `ztunnel` component)

### 3. Gateways

**Istio Gateway** controls traffic entering and leaving the mesh. It's a specialized Envoy proxy deployment that provides:
- Ingress traffic management
- Egress traffic management
- TLS termination and origination

Gateways are configured using custom resources defined in the `pilot/pkg/config/kube/gateway/` directory.

### 4. Security Components

Istio provides comprehensive security features:
- **Authentication**: Using mutual TLS (mTLS) between services
- **Authorization**: Fine-grained access control between services
- **Certificate Management**: Automatic certificate issuance and rotation

These security components are implemented in the `security/` directory.

## Key Code Directories

- `pilot/`: The core of Istiod, including service discovery, config validation, and proxy configuration
- `pkg/`: Shared libraries and components used across Istio
- `security/`: Security-related components including authentication and certificate management
- `istioctl/`: Command-line tool for interacting with Istio
- `operator/`: Istio operator for installation and management
- `samples/`: Example configurations and deployments
- `tests/`: Integration and end-to-end tests

## Data Flow and Communication

1. **Configuration Flow**:
   - User applies Istio configuration using Kubernetes CRDs or `istioctl`
   - Istiod watches for configuration changes
   - Istiod translates configuration into proxy configurations
   - Proxies receive their configuration via xDS (discovery) APIs

2. **Traffic Flow**:
   - Incoming traffic is intercepted by the Envoy proxy
   - Proxy applies configured policies (routing, security, etc.)
   - Traffic is forwarded to the destination service
   - Metrics and telemetry data are collected

## Next Steps

For more details on specific areas of Istio, refer to the following files in this directory:
- `02-control-plane-deep-dive.md`
- `03-data-plane-and-envoy.md`
- `04-security-architecture.md`
- `05-configuration-model.md`
- `06-networking-features.md`
- `07-ambient-mesh.md`
