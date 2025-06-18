#!/bin/bash

# Deploy and Verify Kuma Demo Application Across Multiple Zones
# This script deploys and verifies the Kuma demo app deployment

set -e

echo "🚀 Deploying Kuma Demo Application Across Zones..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} Checking prerequisites..."

# Check if demo_application folder exists
if [ ! -d "demo_application" ]; then
    echo -e "${RED}[ERROR]${NC} demo_application folder not found!"
    echo "Expected files:"
    echo "  manifests/demo_application/redis.yaml"
    echo "  manifests/demo_application/demo-app-zone1.yaml" 
    echo "  manifests/demo_application/demo-app-zone2.yaml"
    echo "  manifests/demo_application/mesh-traffic-permission.yaml"
    echo "  manifests/demo_application/mesh-load-balancing-strategy.yaml"
    exit 1
fi

# Check required files
REQUIRED_FILES=(
    "manifests/demo_application/redis.yaml"
    "manifests/demo_application/demo-app-zone1.yaml"
    "manifests/demo_application/demo-app-zone2.yaml"
    "manifests/demo_application/mesh-traffic-permission.yaml"
    "manifests/demo_application/mesh-load-balancing-strategy.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}[ERROR]${NC} Required file not found: $file"
        exit 1
    fi
done

echo -e "${GREEN}[SUCCESS]${NC} ✓ All required manifest files found"

# Check contexts
CONTEXTS=("k3d-control-plane" "k3d-member-1" "k3d-member-2")
for context in "${CONTEXTS[@]}"; do
    if ! kubectl config get-contexts | grep -q "$context"; then
        echo -e "${RED}[ERROR]${NC} Context $context not found!"
        exit 1
    fi
done

echo -e "${GREEN}[SUCCESS]${NC} ✓ All required Kubernetes contexts found"

echo -e "${BLUE}=== Deploying Applications ===${NC}"

# Deploy Redis on Member-1
echo -e "${GREEN}[INFO]${NC} Deploying Redis on member-1 cluster..."
kubectl --context k3d-member-1 apply -f manifests/demo_application/redis.yaml
echo -e "${GREEN}[SUCCESS]${NC} ✓ Redis deployed on member-1"

# Deploy Demo App v1 on Member-1
echo -e "${GREEN}[INFO]${NC} Deploying Demo App v1 on member-1 cluster..."
kubectl --context k3d-member-1 apply -f manifests/demo_application/demo-app-zone1.yaml
echo -e "${GREEN}[SUCCESS]${NC} ✓ Demo App v1 deployed on member-1"

# Deploy Demo App v2 on Member-2
echo -e "${GREEN}[INFO]${NC} Deploying Demo App v2 on member-2 cluster..."
kubectl --context k3d-member-2 apply -f manifests/demo_application/demo-app-zone2.yaml
echo -e "${GREEN}[SUCCESS]${NC} ✓ Demo App v2 deployed on member-2"

# Apply Traffic Permissions
echo -e "${GREEN}[INFO]${NC} Applying cross-zone traffic permissions..."
kubectl --context k3d-control-plane apply -f manifests/demo_application/mesh-traffic-permission.yaml
echo -e "${GREEN}[SUCCESS]${NC} ✓ MeshTrafficPermission applied"

# Apply Load Balancing Strategy
echo -e "${GREEN}[INFO]${NC} Applying load balancing strategy..."
kubectl --context k3d-control-plane apply -f manifests/demo_application/mesh-load-balancing-strategy.yaml
echo -e "${GREEN}[SUCCESS]${NC} ✓ MeshLoadBalancingStrategy applied"

echo -e "${BLUE}=== Waiting for Deployments ===${NC}"

echo -e "${GREEN}[INFO]${NC} Waiting for Redis to be ready..."
kubectl --context k3d-member-1 wait --for=condition=available --timeout=300s deployment/redis -n kuma-demo

echo -e "${GREEN}[INFO]${NC} Waiting for Demo App v1 to be ready..."
kubectl --context k3d-member-1 wait --for=condition=available --timeout=300s deployment/demo-app-v1 -n kuma-demo

echo -e "${GREEN}[INFO]${NC} Waiting for Demo App v2 to be ready..."
kubectl --context k3d-member-2 wait --for=condition=available --timeout=300s deployment/demo-app-v2 -n kuma-demo

echo -e "${GREEN}[SUCCESS]${NC} ✓ All deployments are ready"

echo -e "${BLUE}=== Verification ===${NC}"

# Check sidecar injection
echo -e "${GREEN}[INFO]${NC} Checking sidecar injection..."
for CLUSTER in k3d-member-1 k3d-member-2; do
    echo ""
    echo -e "${GREEN}[INFO]${NC} Pods in $CLUSTER:"
    kubectl --context $CLUSTER get pods -n kuma-demo -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name"
done

# Check Kuma components
echo ""
echo -e "${GREEN}[INFO]${NC} Checking Kuma dataplanes..."
kubectl config use-context k3d-control-plane
kumactl get dataplanes

echo ""
echo -e "${GREEN}[INFO]${NC} Checking zone status..."
kumactl get zones

echo ""
echo -e "${GREEN}[INFO]${NC} Checking zone ingresses..."
kumactl get zone-ingresses

echo ""
echo -e "${GREEN}[INFO]${NC} Checking zone egresses..."
kumactl get zoneegresses

# Check services and endpoints
echo ""
echo -e "${GREEN}[INFO]${NC} Checking services and endpoints..."
for CLUSTER in k3d-member-1 k3d-member-2; do
    echo ""
    echo -e "${GREEN}[INFO]${NC} Services in $CLUSTER:"
    kubectl --context $CLUSTER get services -n kuma-demo
    
    echo ""
    echo -e "${GREEN}[INFO]${NC} Endpoints in $CLUSTER:"
    kubectl --context $CLUSTER get endpoints -n kuma-demo
done

# Check ServiceInsight objects
echo ""
echo -e "${GREEN}[INFO]${NC} Checking KUMA ServiceInsight objects..."
for CLUSTER in k3d-member-1 k3d-member-2; do
    echo ""
    echo -e "${GREEN}[INFO]${NC} ServiceInsight objects on $CLUSTER:"
    kubectl --context $CLUSTER get serviceinsights -n kuma-demo 2>/dev/null || {
        echo -e "${YELLOW}[WARNING]${NC} No ServiceInsight objects found on $CLUSTER"
    }
done

echo ""
echo -e "${GREEN}[SUCCESS]${NC} 🎉 Deployment and verification complete!"

echo ""
echo -e "${GREEN}[INFO]${NC} Summary:"
echo "- Redis (Zone-1): deployed on member-1 cluster"
echo "- Demo App v1 (Zone-1): deployed on member-1 cluster"  
echo "- Demo App v2 (Zone-2): deployed on member-2 cluster"
echo "- Cross-zone traffic permissions: applied"
echo "- Load balancing strategy: applied"

echo ""
echo -e "${GREEN}[INFO]${NC} Next steps:"
echo "1. Run tests: ./test-cross-zone-connectivity.sh"
echo "2. Access demo app: kubectl --context k3d-member-1 port-forward svc/demo-app -n kuma-demo 5000:5000"
echo "3. Access Kuma GUI: kubectl --context k3d-control-plane port-forward svc/kuma-control-plane -n kuma-system 5681:5681"