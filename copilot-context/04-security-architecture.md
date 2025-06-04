# Istio Security Architecture

## Introduction

Istio's security architecture provides defense-in-depth through strong identity, robust policies, transparent TLS encryption, and authentication/authorization features. This document outlines the security components, their implementation, and how they interact to secure service-to-service communication.

## Core Security Components

Istio's security framework consists of several interconnected components:

1. **Identity Provisioning**: Strong cryptographic identities for services
2. **Certificate Management**: Automatic certificate issuance and rotation
3. **Authentication**: Service-to-service and end-user authentication
4. **Authorization**: Fine-grained access control
5. **Secure Naming**: Mapping service identities to service names

## Identity System

### Service Identity

Every workload in Istio receives a strong identity representing:

- **Service Account**: Kubernetes service account or custom identity
- **Namespace**: Logical grouping of services
- **Trust Domain**: Organizational boundary (e.g., cluster)

Identity is represented as a SPIFFE ID in the format: `spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>`

### Implementation

- **SPIFFE Standard**: Used for identity representation
- **Identity Issuance**: Implemented in `security/pkg/pki/ca/`
- **Certificate Signing**: Citadel signs workload certificates

## Certificate Management System

### Overview

Istio's certificate management system (Citadel) automates:

- Certificate issuance for new workloads
- Certificate rotation before expiration
- Key management for workloads

### Components

1. **Istiod CA**: Central certificate authority (`security/pkg/server/ca/`)
2. **istio-agent**: Local agent that manages certs for proxies
3. **Secret Discovery Service (SDS)**: Securely delivers certificates

### Certificate Lifecycle

1. **Authentication**: Workload authenticates to CA using JWT or platform credentials
2. **CSR Generation**: Workload generates key pair and CSR
3. **Certificate Signing**: CA validates identity and signs certificate
4. **Distribution**: Certificate is securely delivered to workload
5. **Rotation**: Certificates are automatically rotated before expiry

## Authentication

Istio supports two types of authentication:

### 1. Peer Authentication

**Purpose**: Service-to-service authentication using mTLS

**Configuration**: Using `PeerAuthentication` CRD

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

**Implementation**:
- Configured in `pilot/pkg/security/authn/` 
- Enforcement in `pilot/pkg/security/authz/`
- mTLS protocols in `security/pkg/pki/`

**Modes**:
- `STRICT`: Only accept mTLS connections
- `PERMISSIVE`: Accept both mTLS and plaintext traffic
- `DISABLE`: No mTLS

### 2. Request Authentication

**Purpose**: End-user authentication using JWT validation

**Configuration**: Using `RequestAuthentication` CRD

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-example
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  jwtRules:
  - issuer: "issuer-example.com"
    jwksUri: "https://example.com/.well-known/jwks.json"
```

**Implementation**:
- Configuration in `pilot/pkg/security/authn/v1beta1/`
- JWT validation in `pilot/pkg/security/authjwt/`

## Authorization

### Overview

Istio's authorization framework controls access to services within the mesh.

### Authorization Policy

**Configuration**: Using `AuthorizationPolicy` CRD

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: httpbin
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/sleep"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/info*"]
```

**Implementation**:
- Policy validation in `pilot/pkg/config/kube/crd/`
- Policy translation in `pilot/pkg/security/authz/model/`
- Policy enforcement in `pilot/pkg/security/authz/builder/`

**Feature Support**:
- Source-based authorization
- Operation-based authorization
- Origin-based authorization
- Condition-based authorization
- Deny rules and allow rules

## mTLS Implementation

### Certificate Flow

1. **Control Plane (Istiod)**:
   - Acts as a Certificate Authority
   - Issues certificates to workloads
   - Code path: `security/pkg/server/ca/`

2. **istio-agent**:
   - Local proxy on each workload
   - Manages certificate rotation
   - Code path: `pkg/istio-agent/` and `security/pkg/nodeagent/`

3. **SDS Protocol**:
   - Securely delivers certificates to Envoy
   - Implementation in `pilot/pkg/xds/sds.go`

### mTLS Modes

1. **STRICT**: Requires mTLS for all communications
2. **PERMISSIVE**: Allows both mTLS and plaintext
3. **DISABLE**: No mTLS enforcement

### Authentication Policy Resolution

1. Service-specific policies take precedence
2. Namespace-level policies are applied next
3. Mesh-wide policies are used as defaults

## Trust Domain and Multi-cluster

### Trust Domain

A trust domain represents the trust root of a system and is used to uniquely identify a trust authority.

**Implementation**:
- Configuration in `meshconfig.MeshConfig`
- Processing in `security/pkg/pki/util/`

### Cross-cluster Security

For multi-cluster deployments, Istio supports:

- **Shared trust model**: Single CA for all clusters
- **Different trust domains**: CA per cluster with trust mapping
- Implementation in `pilot/pkg/bootstrap/` and `security/pkg/pki/ca/`

## Secret Management

### Secret Discovery Service (SDS)

SDS securely delivers TLS certificates to Envoy without storing them on disk:

1. Envoy requests certificates from istio-agent
2. istio-agent retrieves certificates from Istiod
3. Certificates are provided to Envoy via SDS API

**Implementation**:
- `pilot/pkg/xds/sds.go`
- `pkg/istio-agent/sds/`

### Certificate Rotation

Certificate rotation happens automatically:
- Default workload cert TTL: 24 hours
- Rotation begins at 80% of cert lifetime
- Implementation in `security/pkg/server/ca/server.go`

## Security Customization

### CustomResources

Istio supports custom CA integration through:

- **CertificateSigningRequest API**: For custom certificate signing workflows
- **External CAs**: Pluggable CA interface

### CA Plugins

The CA system is extensible through plugins:
- Implementation in `security/pkg/server/ca/`
- Plugin interface in `security/pkg/pki/ca/provider`

## Security in Ambient Mesh

Ambient mesh implements security through:

### L4 Security (ztunnel)

- mTLS between ztunnels
- Basic authorization policies
- Implementation in the `ztunnel` repository

### L7 Security (Waypoint Proxy)

- Full HTTP-level authorization
- JWT validation
- Advanced routing security
- Implementation in `pilot/pkg/serviceregistry/kube/controller/ambient/`

## Security Debugging and Troubleshooting

### Tools and Endpoints

- **istioctl**: CLI tool for debugging security configs
  - `istioctl authn tls-check`
  - `istioctl authz check`

- **Debug Endpoints**:
  - `/debug/authenticationz`: Authentication policy status
  - `/debug/configz`: Current security configuration

### Common Troubleshooting

- Certificate validation issues
- Authorization policy conflicts
- mTLS configuration mismatches

## Best Practices

1. Enable STRICT mTLS mesh-wide once migration is complete
2. Use namespace-level authorization as a default
3. Follow least-privilege principles for authorization policies
4. Regularly audit security policies
5. Use auto-mTLS for hybrid deployments
