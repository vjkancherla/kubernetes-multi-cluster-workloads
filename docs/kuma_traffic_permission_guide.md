# Understanding Kuma MeshTrafficPermission

## What is MeshTrafficPermission?

MeshTrafficPermission is Kuma's way of controlling which services can communicate with each other in your service mesh. Think of it as a "firewall rule" but for service-to-service communication.

## Why Do You Need It?

### Without mTLS (Default Behavior)
```yaml
# When you create a basic mesh without mTLS
apiVersion: kuma.io/v1alpha1
kind: Mesh
metadata:
  name: default
# No mTLS configuration = permissive mode
```
- **Result**: All services can talk to each other freely
- **Security**: Lower (no encryption, no access control)

### With mTLS (Secure Setup)
```yaml
# When you create a mesh with mTLS (like in your setup)
apiVersion: kuma.io/v1alpha1
kind: Mesh
metadata:
  name: default
spec:
  mtls:
    enabledBackend: ca-1
    backends:
    - name: ca-1
      type: builtin
```
- **Result**: All traffic is encrypted BUT **DENIED BY DEFAULT**
- **Security**: High (encrypted + zero-trust model)
- **Requirement**: You must explicitly allow communication

## How Services Are Identified in Kuma

Kuma automatically assigns tags to each service based on Kubernetes resources:

### Service Tag Format
```
{service-name}_{namespace}_{resource-type}_{port}
```

### Examples
```bash
# For a service named "redis" in namespace "kuma-demo" on port 6379
kuma.io/service: redis_kuma-demo_svc_6379

# For a service named "hello-zone1" in namespace "test-app" on port 80  
kuma.io/service: hello-zone1_test-app_svc_80

# For a pod/deployment without a service (direct pod communication)
kuma.io/service: client_test-app_svc
```

## MeshTrafficPermission Structure

```yaml
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system  # Always in kuma-system namespace
  name: my-permission
spec:
  targetRef:              # WHO can be accessed (destination)
    kind: MeshSubset
    tags:
      kuma.io/service: redis_kuma-demo_svc_6379
  from:                   # WHO can access (source)
    - targetRef:
        kind: MeshSubset
        tags:
          kuma.io/service: demo-app_kuma-demo_svc_5000
      default:
        action: Allow     # WHAT action (Allow/Deny)
```

## Real-World Examples

### 1. Basic Service-to-Service Communication

**Scenario**: Allow `demo-app` to access `redis`

```yaml
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: demo-app-to-redis
spec:
  targetRef:              # Redis can be accessed
    kind: MeshSubset
    tags:
      kuma.io/service: redis_kuma-demo_svc_6379
  from:                   # By demo-app
    - targetRef:
        kind: MeshSubset
        tags:
          kuma.io/service: demo-app_kuma-demo_svc_5000
      default:
        action: Allow
```

### 2. Cross-Zone Communication

**Scenario**: Allow client in zone-1 to access service in zone-2

```yaml
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: cross-zone-access
spec:
  targetRef:              # Service in zone-2
    kind: MeshSubset
    tags:
      kuma.io/service: hello-zone2_test-app_svc_80
  from:                   # Client from any zone
    - targetRef:
        kind: MeshSubset
        tags:
          kuma.io/service: client_test-app_svc
      default:
        action: Allow
```

### 3. Namespace-Wide Permissions (Testing)

**Scenario**: Allow all services in a namespace to communicate

```yaml
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: allow-all-test-app
spec:
  targetRef:              # Any service in the mesh
    kind: Mesh
  from:                   # From any service in test-app namespace
    - targetRef:
        kind: MeshSubset
        tags:
          k8s.kuma.io/namespace: test-app
      default:
        action: Allow
```

### 4. Multiple Sources (Fan-in Pattern)

**Scenario**: Allow multiple services to access a database

```yaml
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: database-access
spec:
  targetRef:              # Database service
    kind: MeshSubset
    tags:
      kuma.io/service: postgres_database_svc_5432
  from:
    - targetRef:          # Frontend can access it
        kind: MeshSubset
        tags:
          kuma.io/service: frontend_web_svc_80
      default:
        action: Allow
    - targetRef:          # Backend can also access it
        kind: MeshSubset
        tags:
          kuma.io/service: backend_api_svc_8080
      default:
        action: Allow
```

## How to Find Service Tags

### Method 1: Using kumactl
```bash
# List all dataplanes to see service tags
kumactl get dataplanes

# Get detailed info about a specific dataplane
kumactl get dataplane {dataplane-name} -o yaml
```

### Method 2: Using kubectl
```bash
# Look at dataplane resources
kubectl get dataplanes -n kuma-system

# Inspect a specific dataplane
kubectl get dataplane {dataplane-name} -n kuma-system -o yaml
```

### Method 3: From Pod Labels
```bash
# Check pod labels (Kuma uses these to generate service tags)
kubectl get pods -n test-app --show-labels
```

## Common Patterns and Best Practices

### 1. Start Permissive for Testing
```yaml
# Allow everything initially
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: allow-all-testing
spec:
  targetRef:
    kind: Mesh
  from:
    - targetRef:
        kind: Mesh
      default:
        action: Allow
```

### 2. Gradually Restrict (Production)
```yaml
# Then create specific rules and remove the permissive one
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: frontend-to-backend-only
spec:
  targetRef:
    kind: MeshSubset
    tags:
      app: backend
  from:
    - targetRef:
        kind: MeshSubset
        tags:
          app: frontend
      default:
        action: Allow
```

### 3. Environment-Based Permissions
```yaml
# Only allow services in the same environment
apiVersion: kuma.io/v1alpha1
kind: MeshTrafficPermission
metadata:
  namespace: kuma-system
  name: same-env-only
spec:
  targetRef:
    kind: MeshSubset
    tags:
      env: production
  from:
    - targetRef:
        kind: MeshSubset
        tags:
          env: production
      default:
        action: Allow
```

## Debugging Traffic Permission Issues

### 1. Check if Dataplanes are Registered
```bash
kumactl get dataplanes
```

### 2. Verify Service Tags
```bash
kumactl get dataplane {name} -o yaml | grep -A 10 "networking:"
```

### 3. Test Connectivity
```bash
# From inside a pod, try to reach another service
kubectl exec -it {pod-name} -- curl -v {service-name}.{namespace}.svc.cluster.local
```

### 4. Check Kuma Proxy Logs
```bash
# Look at the kuma-sidecar logs for traffic denials
kubectl logs {pod-name} -c kuma-sidecar
```

## Key Takeaways

1. **mTLS = Zero Trust**: With mTLS enabled, nothing is allowed by default
2. **Explicit Permissions**: You must create MeshTrafficPermission for each communication path
3. **Service Tags**: Services are identified by auto-generated tags based on K8s resources
4. **Namespace Matters**: MeshTrafficPermission objects live in `kuma-system` namespace
5. **Start Permissive**: Begin with broad permissions for testing, then narrow down for production
6. **Cross-Zone Works**: The same permission model applies across different zones/clusters

This zero-trust approach gives you fine-grained control over service communication, but requires you to be explicit about which services can talk to each other.