#!/bin/bash

# Deploy Kuma Demo Application Across Multiple Zones
# This script deploys the Kuma demo app using manifests from demo_application folder

set -e

echo "🚀 Deploying Kuma Demo Application Across Zones..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} ✓ $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Check if demo_application folder exists
if [ ! -d "demo_application" ]; then
    print_error "demo_application folder not found. Please ensure the manifest files are in the demo_application directory."
    echo ""
    print_status "Expected files:"
    echo "  demo_application/redis.yaml"
    echo "  demo_application/demo-app-zone1.yaml"
    echo "  demo_application/demo-app-zone2.yaml"
    echo "  demo_application/mesh-traffic-permission.yaml"
    echo "  demo_application/mesh-load-balancing-strategy.yaml"
    exit 1
fi

# Check if required manifest files exist
REQUIRED_FILES=(
    "demo_application/redis.yaml"
    "demo_application/demo-app-zone1.yaml"
    "demo_application/demo-app-zone2.yaml"
    "demo_application/mesh-traffic-permission.yaml"
    "demo_application/mesh-load-balancing-strategy.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Required file not found: $file"
        exit 1
    fi
done

print_success "All required manifest files found"

# Check if contexts exist
CONTEXTS=("k3d-control-plane" "k3d-member-1" "k3d-member-2")
for context in "${CONTEXTS[@]}"; do
    if ! kubectl config get-contexts | grep -q "$context"; then
        print_error "Context $context not found. Please ensure your clusters are running."
        exit 1
    fi
done

print_success "All required Kubernetes contexts found"

print_header "Step 1: Deploying Redis on Member-1 (Zone-1)"

print_status "Applying redis.yaml to member-1 cluster..."
kubectl --context k3d-member-1 apply -f demo_application/redis.yaml

print_success "Redis deployed on member-1 cluster (zone-1)"

print_header "Step 2: Deploying Demo App v1 on Member-1 (Zone-1)"

print_status "Applying demo-app-zone1.yaml to member-1 cluster..."
kubectl --context k3d-member-1 apply -f demo_application/demo-app-zone1.yaml

print_success "Demo App v1 deployed on member-1 cluster (zone-1)"

print_header "Step 3: Deploying Demo App v2 on Member-2 (Zone-2)"

print_status "Applying demo-app-zone2.yaml to member-2 cluster..."
kubectl --context k3d-member-2 apply -f demo_application/demo-app-zone2.yaml

print_success "Demo App v2 deployed on member-2 cluster (zone-2)"

print_header "Step 4: Applying Cross-Zone Traffic Permissions"

print_status "Applying mesh-traffic-permission.yaml to control-plane cluster..."
kubectl --context k3d-control-plane apply -f demo_application/mesh-traffic-permission.yaml

print_success "MeshTrafficPermission applied for cross-zone communication"

print_header "Step 5: Applying Cross-Zone LoadBalancing Strategy"

print_status "Applying mesh-load-balancing-strategy.yaml to control-plane cluster..."
kubectl --context k3d-control-plane apply -f demo_application/mesh-load-balancing-strategy.yaml

print_success "MeshLoadBalancingStrategy applied for cross-zone LoadBalancing"

print_header "Step 5: Waiting for Deployments to be Ready"

print_status "Waiting for Redis to be ready..."
kubectl --context k3d-member-1 wait --for=condition=available --timeout=300s deployment/redis -n kuma-demo

print_status "Waiting for Demo App v1 to be ready..."
kubectl --context k3d-member-1 wait --for=condition=available --timeout=300s deployment/demo-app-v1 -n kuma-demo

print_status "Waiting for Demo App v2 to be ready..."
kubectl --context k3d-member-2 wait --for=condition=available --timeout=300s deployment/demo-app-v2 -n kuma-demo

print_success "All deployments are ready"

print_header "Step 6: Verifying Kuma Sidecar Injection"

echo ""
print_status "Checking sidecar injection on member clusters..."

for CLUSTER in k3d-member-1 k3d-member-2; do
    echo ""
    print_status "Pods in $CLUSTER:"
    kubectl --context $CLUSTER get pods -n kuma-demo -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.spec.containers[*].name"
done

print_header "Step 7: Testing Basic Connectivity"

echo ""
print_status "Testing connectivity between zones..."

# Get demo app pod names
DEMO_POD_ZONE1=$(kubectl --context k3d-member-1 get pods -n kuma-demo -l app=demo-app -o jsonpath='{.items[0].metadata.name}')
DEMO_POD_ZONE2=$(kubectl --context k3d-member-2 get pods -n kuma-demo -l app=demo-app -o jsonpath='{.items[0].metadata.name}')

if [ ! -z "$DEMO_POD_ZONE1" ]; then
    print_status "Testing Redis connectivity from Zone-1..."
    if kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- timeout 5 nc -zv redis.kuma-demo.svc.cluster.local 6379 >/dev/null 2>&1; then
        print_success "Redis connectivity from Zone-1: OK"
    else
        print_warning "Redis connectivity from Zone-1: Failed"
    fi
fi

if [ ! -z "$DEMO_POD_ZONE2" ]; then
    print_status "Testing Redis connectivity from Zone-2..."
    if kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- timeout 5 nc -zv redis.kuma-demo.svc.cluster.local 6379 >/dev/null 2>&1; then
        print_success "Redis connectivity from Zone-2: OK"
    else
        print_warning "Redis connectivity from Zone-2: Failed"
    fi
fi

# Test demo app health
if [ ! -z "$DEMO_POD_ZONE1" ]; then
    print_status "Testing Demo App v1 health..."
    if kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- timeout 10 wget -q -O /dev/null http://localhost:5000 2>/dev/null; then
        print_success "Demo App v1 health check: OK"
    else
        print_warning "Demo App v1 health check: Failed"
    fi
fi

if [ ! -z "$DEMO_POD_ZONE2" ]; then
    print_status "Testing Demo App v2 health..."
    if kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- timeout 10 wget -q -O /dev/null http://localhost:5000 2>/dev/null; then
        print_success "Demo App v2 health check: OK"
    else
        print_warning "Demo App v2 health check: Failed"
    fi
fi

print_header "Step 8: Verifying Multi-Zone Service Discovery"

echo ""
print_status "Checking Kuma dataplanes..."
kubectl config use-context k3d-control-plane
kumactl get dataplanes

echo ""
print_status "Checking zone status..."
kumactl get zones

echo ""
print_status "Checking zone ingresses..."
kumactl get zone-ingresses

print_header "Step 9: Verifying ServiceInsight Objects"

echo ""
print_status "Checking ServiceInsight objects on member clusters..."

echo ""
print_status "ServiceInsight objects on member-1 (Zone-1):"
kubectl --context k3d-member-1 get serviceinsights -n kuma-demo -o wide 2>/dev/null || {
    print_warning "No ServiceInsight objects found on member-1 or ServiceInsight CRD not available"
}

echo ""
print_status "ServiceInsight objects on member-2 (Zone-2):"
kubectl --context k3d-member-2 get serviceinsights -n kuma-demo -o wide 2>/dev/null || {
    print_warning "No ServiceInsight objects found on member-2 or ServiceInsight CRD not available"
}

echo ""
print_status "Detailed ServiceInsight information:"

# Check the all-services-default ServiceInsight which contains all services
echo ""
print_status "All-services ServiceInsight on member-1:"
ALL_SERVICES_SI_M1=$(kubectl --context k3d-member-1 get serviceinsights -n kuma-demo --no-headers -o custom-columns=":metadata.name" | grep "^all-services-default" | head -1)
if [ ! -z "$ALL_SERVICES_SI_M1" ]; then
    kubectl --context k3d-member-1 get serviceinsight $ALL_SERVICES_SI_M1 -n kuma-demo -o yaml 2>/dev/null
else
    print_warning "all-services-default ServiceInsight not found on member-1"
fi

echo ""
print_status "All-services ServiceInsight on member-2:"
ALL_SERVICES_SI_M2=$(kubectl --context k3d-member-2 get serviceinsights -n kuma-demo --no-headers -o custom-columns=":metadata.name" | grep "^all-services-default" | head -1)
if [ ! -z "$ALL_SERVICES_SI_M2" ]; then
    kubectl --context k3d-member-2 get serviceinsight $ALL_SERVICES_SI_M2 -n kuma-demo -o yaml 2>/dev/null
else
    print_warning "all-services-default ServiceInsight not found on member-2"
fi

echo ""
print_status "Extracting demo-app service info from all-services ServiceInsight:"
if [ ! -z "$ALL_SERVICES_SI_M1" ]; then
    kubectl --context k3d-member-1 get serviceinsight $ALL_SERVICES_SI_M1 -n kuma-demo -o jsonpath='{.spec.services.demo-app_kuma-demo_svc_5000}' 2>/dev/null && echo "" || {
        print_warning "demo-app service info not found in member-1 ServiceInsight"
    }
else
    print_warning "Cannot extract demo-app info - ServiceInsight not found on member-1"
fi

echo ""
print_status "Extracting redis service info from all-services ServiceInsight:"
if [ ! -z "$ALL_SERVICES_SI_M1" ]; then
    kubectl --context k3d-member-1 get serviceinsight $ALL_SERVICES_SI_M1 -n kuma-demo -o jsonpath='{.spec.services.redis_kuma-demo_svc_6379}' 2>/dev/null && echo "" || {
        print_warning "redis service info not found in member-1 ServiceInsight"
    }
else
    print_warning "Cannot extract redis info - ServiceInsight not found on member-1"
fi

# Check service status and availability
print_header "Step 10: Verifying Service Availability Across Zones"

echo ""
print_status "Checking service endpoints and status..."

# Check services on both clusters
for CLUSTER in k3d-member-1 k3d-member-2; do
    echo ""
    print_status "Services in $CLUSTER:"
    kubectl --context $CLUSTER get services -n kuma-demo -o wide
    
    echo ""
    print_status "Endpoints in $CLUSTER:"
    kubectl --context $CLUSTER get endpoints -n kuma-demo -o wide
done

# Verify cross-zone service discovery from ServiceInsight perspective
echo ""
print_status "Analyzing ServiceInsight status for cross-zone availability..."

# Function to check ServiceInsight status for specific service within all-services-default
check_service_insight_status() {
    local cluster=$1
    local service=$2
    local service_key=$3
    
    echo ""
    print_status "Checking $service availability on $cluster:"
    
    # Get the all-services ServiceInsight name (with dynamic suffix)
    ALL_SERVICES_SI=$(kubectl --context $cluster get serviceinsights -n kuma-demo --no-headers -o custom-columns=":metadata.name" | grep "^all-services-default" | head -1)
    
    if [ ! -z "$ALL_SERVICES_SI" ]; then
        # Get service information from all-services ServiceInsight (.spec.services)
        SERVICE_INFO=$(kubectl --context $cluster get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.$service_key}" 2>/dev/null)
        if [ ! -z "$SERVICE_INFO" ] && [ "$SERVICE_INFO" != "null" ]; then
            print_success "$service found in all-services ServiceInsight ($ALL_SERVICES_SI) on $cluster"
            
            # Check for online dataplanes
            DATAPLANES=$(kubectl --context $cluster get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.$service_key.dataplanes.online}" 2>/dev/null)
            if [ ! -z "$DATAPLANES" ] && [ "$DATAPLANES" != "0" ] && [ "$DATAPLANES" != "null" ]; then
                print_success "$service has $DATAPLANES online dataplane(s) on $cluster"
            else
                print_warning "$service has no online dataplanes on $cluster"
            fi
            
            # Check service status
            STATUS=$(kubectl --context $cluster get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.$service_key.status}" 2>/dev/null)
            if [ ! -z "$STATUS" ]; then
                print_status "$service status: $STATUS on $cluster"
            fi
            
            # Check zones
            ZONES=$(kubectl --context $cluster get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.$service_key.zones[*]}" 2>/dev/null)
            if [ ! -z "$ZONES" ]; then
                print_status "$service available in zones: $ZONES on $cluster"
            fi
        else
            print_warning "$service not found in all-services ServiceInsight on $cluster"
        fi
    else
        print_warning "all-services-default ServiceInsight not found on $cluster"
    fi
}

# Check ServiceInsight for key services (with correct service keys including ports)
check_service_insight_status "k3d-member-1" "demo-app" "demo-app_kuma-demo_svc_5000"
check_service_insight_status "k3d-member-2" "demo-app" "demo-app_kuma-demo_svc_5000"
check_service_insight_status "k3d-member-1" "redis" "redis_kuma-demo_svc_6379"
check_service_insight_status "k3d-member-2" "redis" "redis_kuma-demo_svc_6379"

print_header "Step 11: Testing Cross-Zone Load Balancing"

echo ""
print_status "Testing cross-zone service connectivity (zone-aware routing)..."

if [ ! -z "$DEMO_POD_ZONE1" ]; then
    print_status "Making requests from Zone-1 to demo-app service..."
    RESPONSES=$(kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- timeout 20 sh -c '
    for i in $(seq 1 10); do
      wget -q -O - http://demo-app.kuma-demo.svc.cluster.local:5000/version 2>/dev/null || echo "failed"
      sleep 0.5
    done
    ' 2>/dev/null)
    
    # Count different versions
    V1_COUNT=$(echo "$RESPONSES" | grep -o '"version":"1.0"' | wc -l)
    V2_COUNT=$(echo "$RESPONSES" | grep -o '"version":"2.0"' | wc -l)
    FAILED_COUNT=$(echo "$RESPONSES" | grep -c "failed")
    
    if echo "$RESPONSES" | grep -q "version"; then
        print_success "Cross-zone service connectivity working"
        echo "Response distribution: v1.0=$V1_COUNT, v2.0=$V2_COUNT, failed=$FAILED_COUNT"
        
        if [ "$V1_COUNT" -gt 0 ] && [ "$V2_COUNT" -gt 0 ]; then
            print_success "True cross-zone load balancing confirmed!"
            print_status "Traffic is distributed across both zones"
        elif [ "$V1_COUNT" -gt 0 ] || [ "$V2_COUNT" -gt 0 ]; then
            print_warning "Zone-aware routing still active (configuration may need more time)"
            print_status "Try running the test again in a few moments"
        fi
    else
        print_warning "Cross-zone service connectivity test inconclusive"
    fi
fi

if [ ! -z "$DEMO_POD_ZONE2" ]; then
    echo ""
    print_status "Making requests from Zone-2 to demo-app service..."
    RESPONSES_Z2=$(kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- timeout 20 sh -c '
    for i in $(seq 1 10); do
      wget -q -O - http://demo-app.kuma-demo.svc.cluster.local:5000/version 2>/dev/null || echo "failed"
      sleep 0.5
    done
    ' 2>/dev/null)
    
    # Count different versions from Zone-2
    V1_COUNT_Z2=$(echo "$RESPONSES_Z2" | grep -o '"version":"1.0"' | wc -l)
    V2_COUNT_Z2=$(echo "$RESPONSES_Z2" | grep -o '"version":"2.0"' | wc -l)
    FAILED_COUNT_Z2=$(echo "$RESPONSES_Z2" | grep -c "failed")
    
    if echo "$RESPONSES_Z2" | grep -q "version"; then
        print_success "Cross-zone service connectivity from Zone-2 working"
        echo "Response distribution: v1.0=$V1_COUNT_Z2, v2.0=$V2_COUNT_Z2, failed=$FAILED_COUNT_Z2"
        
        if [ "$V1_COUNT_Z2" -gt 0 ] && [ "$V2_COUNT_Z2" -gt 0 ]; then
            print_success "True cross-zone load balancing confirmed from Zone-2!"
        fi
    fi
fi

print_header "Deployment Complete! 🎉"

echo ""
print_success "Demo application deployed successfully across zones:"
print_status "- Redis (Zone-1): member-1 cluster"
print_status "- Demo App v1 (Zone-1): member-1 cluster"  
print_status "- Demo App v2 (Zone-2): member-2 cluster"

echo ""
print_status "Manifest files used:"
for file in "${REQUIRED_FILES[@]}"; do
    echo "  ✓ $file"
done

echo ""
print_status "Next steps:"
echo "1. Run comprehensive tests:"
echo "   ./test-cross-zone-connectivity.sh"
echo ""
echo "2. Access the demo app:"
echo "   kubectl --context k3d-member-1 port-forward svc/demo-app -n kuma-demo 5000:5000"
echo "   Open: http://localhost:5000"
echo ""
echo "3. Monitor the Kuma GUI:"
echo "   kubectl --context k3d-control-plane port-forward svc/kuma-control-plane -n kuma-system 5681:5681"
echo "   Open: http://localhost:5681/gui"
echo ""
echo "4. Check ServiceInsight objects for service discovery:"
echo "   # View all ServiceInsight objects (should show all-services-default-*)"
echo "   kubectl --context k3d-member-1 get serviceinsights -n kuma-demo"
echo "   kubectl --context k3d-member-2 get serviceinsights -n kuma-demo"
echo ""
echo "   # View detailed all-services ServiceInsight (replace with actual name)"
echo "   SI_NAME=\$(kubectl --context k3d-member-1 get serviceinsights -n kuma-demo --no-headers -o custom-columns=':metadata.name' | grep '^all-services-default')"
echo "   kubectl --context k3d-member-1 get serviceinsight \$SI_NAME -n kuma-demo -o yaml"
echo ""
echo "   # Extract specific service info from all-services ServiceInsight"
echo "   kubectl --context k3d-member-1 get serviceinsight \$SI_NAME -n kuma-demo -o jsonpath='{.spec.services}'"
echo ""
echo "Optional: Remove cross-zone load balancing (restore zone-aware routing):"
echo "kubectl --context k3d-control-plane delete meshloadbalancingstrategy disable-zone-preference -n kuma-system"
echo ""
echo "7. Test load balancing manually:"
echo "   # Make multiple requests to see different versions"
echo ""
print_status "Manual testing commands:"
echo "   for i in {1..10}; do kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- wget -q -O - http://demo-app.kuma-demo.svc.cluster.local:5000/version; done"
echo ""
echo "   # Check which version responds (should see both v1.0 and v2.0 with load balancing enabled)"
echo "   for i in {1..10}; do kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- wget -q -O - http://demo-app.kuma-demo.svc.cluster.local:5000/version; done"
echo ""
echo "6. View applied MeshLoadBalancingStrategy:"
echo "   kubectl --context k3d-control-plane get meshloadbalancingstrategies -n kuma-system"
echo "   kubectl --context k3d-control-plane get meshloadbalancingstrategy disable-zone-preference -n kuma-system -o yaml"

echo ""
print_status "Troubleshooting:"
echo "- Check pod status: kubectl --context k3d-member-1 get pods -n kuma-demo"
echo "- View sidecar logs: kubectl --context k3d-member-1 logs [pod-name] -c kuma-sidecar -n kuma-demo"
echo "- Check zone connectivity: kumactl get zones"
echo "- Verify traffic permissions: kubectl --context k3d-control-plane get meshtrafficpermissions -n kuma-system"
echo "- Examine ServiceInsight objects: SI_NAME=\$(kubectl --context k3d-member-1 get serviceinsights -n kuma-demo --no-headers -o custom-columns=':metadata.name' | grep '^all-services-default'); kubectl --context k3d-member-1 get serviceinsight \$SI_NAME -n kuma-demo -o yaml"
echo "- View applied load balancing policies: kubectl --context k3d-control-plane get meshloadbalancingstrategies -n kuma-system"
echo "- Check service endpoints: kubectl --context k3d-member-1 get endpoints -n kuma-demo"