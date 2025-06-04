# Istio Ambient Mesh

## Introduction

Istio Ambient Mesh is a new architecture that provides a sidecarless deployment model for the service mesh. It separates the L4 and L7 functionality of Istio into different layers, enabling incremental adoption and reducing the resource overhead associated with traditional sidecar deployments. This document explains the ambient architecture, components, and implementation details.

## Ambient Mesh Architecture

### Overview

Ambient Mesh introduces a new multi-tier architecture:

1. **L4 Layer (ztunnel)**: Handles secure connectivity, identity, and basic telemetry
2. **L7 Layer (waypoint proxy)**: Optional component for advanced L7 features when needed
3. **CNI Plugin**: Enables capturing and redirecting traffic without sidecars

This separation allows for incremental adoption - L4 security features can be deployed mesh-wide with minimal overhead, while L7 features can be added selectively where needed.

### Key Architectural Benefits

1. **Reduced Resource Overhead**: Eliminates per-pod sidecar containers
2. **Simplified Operations**: Zero-touch workload onboarding
3. **Incremental Feature Adoption**: Deploy only what's needed
4. **Transparent Security**: Automatic mTLS for all services
5. **Flexible Policy Model**: L4 vs. L7 policy enforcement

## Core Components

### ztunnel

The ztunnel (zero-trust tunnel) is a Rust-based L4 proxy deployed as a DaemonSet on each node:

**Responsibilities**:
- Secure service-to-service communication (mTLS)
- Identity verification and certificate management
- Basic traffic authorization
- L4 telemetry collection
- HBONE protocol implementation

**Implementation**:
- Repository: [istio/ztunnel](https://github.com/istio/ztunnel)
- Rust-based for performance and memory efficiency
- Deployed as a DaemonSet
- One ztunnel per node

### Waypoint Proxy

The waypoint proxy is an Envoy-based L7 proxy that provides advanced traffic management features:

**Responsibilities**:
- HTTP routing and traffic splitting
- Advanced authorization policies
- Request/response transformation
- Telemetry enrichment
- Protocol-aware features (HTTP, gRPC, etc.)

**Implementation**:
- Based on Envoy proxy
- Deployed as Kubernetes deployments
- Scaled independently per namespace/service
- Code path: `pilot/pkg/serviceregistry/kube/controller/ambient/waypoint.go`

### CNI Plugin

The Istio CNI plugin enables traffic capture without sidecars:

**Responsibilities**:
- Intercept and redirect traffic to ztunnel
- Configure pod networking for ambient capture
- Apply node-level iptables/ebpf rules

**Implementation**:
- Code in `cni/pkg/ambient/`
- Deployed as a DaemonSet
- Compatible with common CNI providers

## Network Traffic Flow

### Inbound Traffic Flow (L4 Only)

1. Traffic arrives at destination node
2. CNI redirects traffic to local ztunnel
3. ztunnel performs L4 authentication
4. Traffic is forwarded to destination pod

```
Client → Node → ztunnel → Destination Pod
```

### Inbound Traffic Flow (With L7/Waypoint)

1. Traffic arrives at destination node
2. CNI redirects traffic to local ztunnel
3. ztunnel routes traffic to waypoint proxy
4. Waypoint applies L7 policies
5. Traffic returns via ztunnel to destination pod

```
Client → Node → ztunnel → Waypoint Proxy → ztunnel → Destination Pod
```

### Outbound Traffic Flow

1. Pod sends outbound traffic
2. CNI redirects to local ztunnel
3. ztunnel establishes secure connection to destination ztunnel
4. Traffic is forwarded to destination (via waypoint if needed)

```
Source Pod → ztunnel → [Waypoint] → Destination ztunnel → Destination Pod
```

## HBONE Protocol

### Overview

HBONE (HTTP-Based Overlay Network) is the protocol used for service-to-service communication:

- Tunnels TCP connections over HTTP/2 CONNECT
- Provides a secure transport layer with mTLS
- Enables efficient connection multiplexing
- Traverses NATs and proxies easily

### Implementation

- Protocol implementation in `pkg/hbone/`
- Client/server in `pkg/hbone/server.go` and `pkg/hbone/client.go`
- Used between ztunnels for node-to-node communication

## Workload API

Ambient introduces a new workload-oriented API for ztunnel:

### Key API Types

1. **`Workload`**: Represents a service instance
2. **`WorkloadService`**: Maps workloads to services
3. **`Authorization`**: L4 authorization policies

### API Implementation

- Defined in `pkg/workloadapi/`
- Transport over xDS protocol with custom resources
- Optimized for efficient updates

## Security in Ambient Mesh

### Identity and Authentication

1. **Workload Identity**: Same SPIFFE identity model as sidecars
2. **Certificate Management**: Through ztunnel (no per-pod certificate)
3. **Authentication**: mTLS enforced at ztunnel layer

### Authorization Models

1. **L4 Authorization**: Applied at ztunnel
   - Source/destination identity
   - IP/port restrictions
   - Implementation: `pilot/pkg/serviceregistry/kube/controller/ambient/authorization.go`

2. **L7 Authorization**: Applied at waypoint
   - Path/method/header based rules
   - JWT validation
   - Implementation: `pilot/pkg/security/authz/builder/builder.go`

## Configuration Model

### Workload Capture

Workloads are captured into the mesh via namespace labeling:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
  labels:
    istio.io/dataplane-mode: ambient
```

### Waypoint Configuration

Waypoint proxies are configured via `Gateway` resources:

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: Gateway
metadata:
  name: example-waypoint
  annotations:
    istio.io/service-account: waypoint-sa
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
```

### Traffic Management

The same Istio traffic management resources work with ambient:

- `VirtualService`: Applied at waypoint proxies
- `DestinationRule`: Applied at waypoint proxies
- `AuthorizationPolicy`: Split between ztunnel (L4) and waypoint (L7)

## Implementation Details

### Controller Architecture

Ambient introduces specialized controllers for the architecture:

1. **Ambient Controller**: 
   - Tracks workloads in ambient mode
   - Implementation: `pilot/pkg/serviceregistry/kube/controller/ambient/ambientindex.go`

2. **Waypoint Controller**:
   - Manages waypoint deployments
   - Implementation: `pilot/pkg/serviceregistry/kube/controller/ambient/waypoint.go`

3. **Policy Controllers**:
   - Transform Istio policies for ambient
   - Implementation: `pilot/pkg/serviceregistry/kube/controller/ambient/policies.go`

### Resource Management

Ambient optimizes resource utilization:

1. **Shared ztunnel**: One ztunnel per node, regardless of pod count
2. **On-demand Waypoints**: Only created when L7 features needed
3. **Memory Optimization**: Rust-based ztunnel optimizes memory use

### Scalability Considerations

Ambient improves scalability in several dimensions:

1. **Node-level Proxies**: Scales with nodes, not pods
2. **Reduced Resource Usage**: Lower CPU/memory overhead
3. **Incremental Feature Adoption**: Deploy only what's needed

## Compatibility

### Sidecar Interoperation

Ambient mesh can coexist with traditional sidecar deployments:

- Services can communicate across deployment modes
- Policies are applied appropriately based on mode
- Implementation: `pilot/pkg/serviceregistry/kube/controller/ambient/sidecar_interop.go`

### Platform Compatibility

Ambient mesh is designed to work across environments:

- Kubernetes
- Multi-cluster deployments
- Various CNI providers

## Monitoring and Debugging

### Telemetry Collection

Ambient collects metrics at multiple points:

1. **ztunnel Metrics**: L4 connection metrics
2. **Waypoint Metrics**: L7 request metrics
3. **Control Plane Metrics**: Configuration metrics

### Diagnostic Tools

Tools for troubleshooting ambient deployments:

1. **istioctl ambient**: CLI for ambient status
2. **ztunnel logs**: Debug logs from ztunnel
3. **API Server Status**: Configuration and readiness checks

## Upgrade and Migration

### Migration from Sidecars

Process for migrating from sidecar to ambient:

1. Deploy ambient components
2. Label namespaces for ambient mode
3. Remove sidecar injector configuration
4. Restart workloads to remove sidecars

### Version Upgrade Strategy

Upgrading ambient components:

1. Upgrade control plane (istiod)
2. Update CNI plugin
3. Rolling upgrade of ztunnel DaemonSet
4. Update waypoint proxies

## Limitations and Future Work

### Current Limitations

1. **Alpha Status**: Not yet production-ready
2. **Feature Parity**: Some advanced sidecar features not yet available
3. **Performance Tuning**: Ongoing optimizations

### Roadmap Items

1. **BPF Integration**: Improved traffic interception
2. **Advanced Waypoint Features**: More L7 capabilities
3. **Enhanced Multi-cluster**: Better cross-cluster support
4. **Production Readiness**: Stability and performance improvements

## Reference Architecture

The ambient mode reference architecture is available in the Istio repository:

- Location: `samples/ambient-argo/`
- Includes production deployment examples
- Contains upgrade and operations guidance

## Comparison with Sidecar Model

| Feature | Sidecar Model | Ambient Model |
|---------|---------------|---------------|
| Resource Usage | Proxy per pod | Shared proxy per node |
| Deployment | Injection required | Zero-touch |
| Data Path | Pod → Local Envoy → Destination | Pod → ztunnel → [waypoint] → Destination |
| L7 Features | Always available | On-demand (waypoint) |
| Init Container | Required | Not needed |
| Memory Overhead | Higher | Lower |
| Security | Pod-level | Node-level + Waypoint |

## Conclusion

Ambient mesh represents a significant architectural evolution for Istio, providing a more efficient and flexible service mesh implementation. While still in alpha, it offers a promising path forward for organizations seeking the benefits of a service mesh with reduced operational complexity and resource overhead.
