#!/bin/bash

# Test Cross-Zone Connectivity for Kuma Demo Application
# This script tests connectivity and load balancing between zones

set -e

echo "🧪 Testing Cross-Zone Connectivity..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Basic Connectivity Tests ===${NC}"

# Get pod names
DEMO_POD_ZONE1=$(kubectl --context k3d-member-1 get pods -n kuma-demo -l app=demo-app -o jsonpath='{.items[0].metadata.name}')
DEMO_POD_ZONE2=$(kubectl --context k3d-member-2 get pods -n kuma-demo -l app=demo-app -o jsonpath='{.items[0].metadata.name}')

if [ -z "$DEMO_POD_ZONE1" ]; then
    echo -e "${RED}[ERROR]${NC} No demo app pod found in zone-1"
    exit 1
fi

if [ -z "$DEMO_POD_ZONE2" ]; then
    echo -e "${RED}[ERROR]${NC} No demo app pod found in zone-2"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Found pods: $DEMO_POD_ZONE1 (zone-1), $DEMO_POD_ZONE2 (zone-2)"

# Test Redis connectivity from Zone-1 using Kuma mesh URL
echo -e "${GREEN}[INFO]${NC} Testing Redis connectivity from Zone-1 (via Kuma mesh)..."
if kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- timeout 5 nc -zv redis.kuma-demo.svc.6379.mesh 80 >/dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS]${NC} ✓ Redis mesh connectivity from Zone-1: OK"
else
    echo -e "${YELLOW}[WARNING]${NC} Redis mesh connectivity from Zone-1: Failed"
fi

# Test Redis connectivity from Zone-2 using Kuma mesh URL
echo -e "${GREEN}[INFO]${NC} Testing Redis connectivity from Zone-2 (via Kuma mesh)..."
if kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- timeout 5 nc -zv redis.kuma-demo.svc.6379.mesh 80 >/dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS]${NC} ✓ Redis mesh connectivity from Zone-2: OK"
else
    echo -e "${YELLOW}[WARNING]${NC} Redis mesh connectivity from Zone-2: Failed"
fi

# Test demo app health - Zone 1
echo -e "${GREEN}[INFO]${NC} Testing Demo App v1 health..."
if kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- timeout 10 wget -q -O /dev/null http://localhost:5000 2>/dev/null; then
    echo -e "${GREEN}[SUCCESS]${NC} ✓ Demo App v1 health check: OK"
else
    echo -e "${YELLOW}[WARNING]${NC} Demo App v1 health check: Failed"
fi

# Test demo app health - Zone 2
echo -e "${GREEN}[INFO]${NC} Testing Demo App v2 health..."
if kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- timeout 10 wget -q -O /dev/null http://localhost:5000 2>/dev/null; then
    echo -e "${GREEN}[SUCCESS]${NC} ✓ Demo App v2 health check: OK"
else
    echo -e "${YELLOW}[WARNING]${NC} Demo App v2 health check: Failed"
fi

echo -e "${BLUE}=== ServiceInsight Analysis ===${NC}"

# Check ServiceInsight for demo-app service
for CLUSTER in k3d-member-1 k3d-member-2; do
    echo ""
    echo -e "${GREEN}[INFO]${NC} Checking ServiceInsight on $CLUSTER..."
    
    ALL_SERVICES_SI=$(kubectl --context $CLUSTER get serviceinsights -n kuma-demo --no-headers -o custom-columns=":metadata.name" | grep "^all-services-default" | head -1)
    
    if [ ! -z "$ALL_SERVICES_SI" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} ✓ Found ServiceInsight: $ALL_SERVICES_SI"
        
        # Check demo-app service info
        DEMO_SERVICE_INFO=$(kubectl --context $CLUSTER get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.demo-app_kuma-demo_svc_5000}" 2>/dev/null)
        if [ ! -z "$DEMO_SERVICE_INFO" ] && [ "$DEMO_SERVICE_INFO" != "null" ]; then
            echo -e "${GREEN}[SUCCESS]${NC} ✓ demo-app service found in ServiceInsight"
            
            # Check online dataplanes
            DATAPLANES=$(kubectl --context $CLUSTER get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.demo-app_kuma-demo_svc_5000.dataplanes.online}" 2>/dev/null)
            if [ ! -z "$DATAPLANES" ] && [ "$DATAPLANES" != "0" ] && [ "$DATAPLANES" != "null" ]; then
                echo -e "${GREEN}[SUCCESS]${NC} ✓ demo-app has $DATAPLANES online dataplane(s)"
            fi
            
            # Check zones
            ZONES=$(kubectl --context $CLUSTER get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.demo-app_kuma-demo_svc_5000.zones[*]}" 2>/dev/null)
            if [ ! -z "$ZONES" ]; then
                echo -e "${GREEN}[INFO]${NC} demo-app available in zones: $ZONES"
            fi
        else
            echo -e "${YELLOW}[WARNING]${NC} demo-app service not found in ServiceInsight"
        fi
        
        # Check redis service info
        REDIS_SERVICE_INFO=$(kubectl --context $CLUSTER get serviceinsight $ALL_SERVICES_SI -n kuma-demo -o jsonpath="{.spec.services.redis_kuma-demo_svc_6379}" 2>/dev/null)
        if [ ! -z "$REDIS_SERVICE_INFO" ] && [ "$REDIS_SERVICE_INFO" != "null" ]; then
            echo -e "${GREEN}[SUCCESS]${NC} ✓ redis service found in ServiceInsight"
        fi
    else
        echo -e "${YELLOW}[WARNING]${NC} all-services-default ServiceInsight not found"
    fi
done

echo -e "${BLUE}=== Cross-Zone Load Balancing Tests ===${NC}"

# Test from Zone-1
echo ""
echo -e "${GREEN}[INFO]${NC} Testing cross-zone load balancing from Zone-1..."

SERVICE_URL="http://demo-app.kuma-demo.svc.5000.mesh:80/version"
echo -e "${GREEN}[INFO]${NC} Using Kuma mesh URL: $SERVICE_URL"

# Create a more reliable test function
echo -e "${GREEN}[INFO]${NC} Running 10 individual requests..."

RESPONSES=""
V1_COUNT=0
V2_COUNT=0
FAILED_COUNT=0

for i in {1..10}; do
    echo -n "Request $i: "
    RESPONSE=$(kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- wget -q -O - "$SERVICE_URL" 2>/dev/null || echo "failed")
    
    if echo "$RESPONSE" | grep -q '"version":"1.0"'; then
        echo "v1.0"
        V1_COUNT=$((V1_COUNT + 1))
    elif echo "$RESPONSE" | grep -q '"version":"2.0"'; then
        echo "v2.0"
        V2_COUNT=$((V2_COUNT + 1))
    elif echo "$RESPONSE" | grep -q "failed"; then
        echo "FAILED"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    else
        echo "Unknown response: $RESPONSE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    sleep 0.5
done

# Analyze responses from Zone-1
echo "Response distribution from Zone-1: v1.0=$V1_COUNT, v2.0=$V2_COUNT, failed=$FAILED_COUNT"

if [ $((V1_COUNT + V2_COUNT)) -gt 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} ✓ Cross-zone service connectivity working from Zone-1"
    
    if [ "$V1_COUNT" -gt 0 ] && [ "$V2_COUNT" -gt 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} ✓ Cross-zone load balancing confirmed from Zone-1!"
        echo -e "${GREEN}[INFO]${NC} Traffic is distributed across both zones"
    elif [ "$V1_COUNT" -gt 0 ] || [ "$V2_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} Zone-aware routing may still be active"
        echo -e "${GREEN}[INFO]${NC} Configuration may need more time to propagate"
    fi
else
    echo -e "${RED}[ERROR]${NC} Cross-zone service connectivity failed from Zone-1"
fi

# Test from Zone-2 with the same reliable method
echo ""
echo -e "${GREEN}[INFO]${NC} Testing cross-zone load balancing from Zone-2..."
echo -e "${GREEN}[INFO]${NC} Using Kuma mesh URL: $SERVICE_URL"
echo -e "${GREEN}[INFO]${NC} Running 10 individual requests..."

V1_COUNT_Z2=0
V2_COUNT_Z2=0
FAILED_COUNT_Z2=0

for i in {1..10}; do
    echo -n "Request $i: "
    RESPONSE_Z2=$(kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- wget -q -O - "$SERVICE_URL" 2>/dev/null || echo "failed")
    
    if echo "$RESPONSE_Z2" | grep -q '"version":"1.0"'; then
        echo "v1.0"
        V1_COUNT_Z2=$((V1_COUNT_Z2 + 1))
    elif echo "$RESPONSE_Z2" | grep -q '"version":"2.0"'; then
        echo "v2.0"
        V2_COUNT_Z2=$((V2_COUNT_Z2 + 1))
    elif echo "$RESPONSE_Z2" | grep -q "failed"; then
        echo "FAILED"
        FAILED_COUNT_Z2=$((FAILED_COUNT_Z2 + 1))
    else
        echo "Unknown response: $RESPONSE_Z2"
        FAILED_COUNT_Z2=$((FAILED_COUNT_Z2 + 1))
    fi
    
    sleep 0.5
done

# Analyze responses from Zone-2
echo "Response distribution from Zone-2: v1.0=$V1_COUNT_Z2, v2.0=$V2_COUNT_Z2, failed=$FAILED_COUNT_Z2"

if [ $((V1_COUNT_Z2 + V2_COUNT_Z2)) -gt 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} ✓ Cross-zone service connectivity working from Zone-2"
    
    if [ "$V1_COUNT_Z2" -gt 0 ] && [ "$V2_COUNT_Z2" -gt 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} ✓ Cross-zone load balancing confirmed from Zone-2!"
        echo -e "${GREEN}[INFO]${NC} Traffic is distributed across both zones"
    fi
else
    echo -e "${RED}[ERROR]${NC} Cross-zone service connectivity failed from Zone-2"
fi

echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"

# Overall summary
TOTAL_V1=$((V1_COUNT + V1_COUNT_Z2))
TOTAL_V2=$((V2_COUNT + V2_COUNT_Z2))
TOTAL_FAILED=$((FAILED_COUNT + FAILED_COUNT_Z2))

echo "Overall results across both zones:"
echo "- Total v1.0 responses: $TOTAL_V1"
echo "- Total v2.0 responses: $TOTAL_V2"
echo "- Total failed requests: $TOTAL_FAILED"

if [ "$TOTAL_V1" -gt 0 ] && [ "$TOTAL_V2" -gt 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} 🎉 Cross-zone load balancing is working correctly!"
    echo -e "${GREEN}[INFO]${NC} Traffic is being distributed across both application versions in different zones"
elif [ "$TOTAL_FAILED" -eq 0 ] && [ $((TOTAL_V1 + TOTAL_V2)) -gt 0 ]; then
    echo -e "${YELLOW}[WARNING]${NC} Connectivity is working but load balancing may need more time"
    echo -e "${GREEN}[INFO]${NC} Try running the test again in a few minutes"
else
    echo -e "${RED}[ERROR]${NC} Issues detected with cross-zone connectivity"
fi

echo ""
echo -e "${GREEN}[INFO]${NC} Manual testing commands:"
echo "# Test from Zone-1 (via Kuma mesh):"
echo "kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- wget -q -O - http://demo-app.kuma-demo.svc.5000.mesh:80/version"
echo ""
echo "# Test from Zone-2 (via Kuma mesh):"
echo "kubectl --context k3d-member-2 exec -n kuma-demo $DEMO_POD_ZONE2 -c demo-app -- wget -q -O - http://demo-app.kuma-demo.svc.5000.mesh:80/version"
echo ""
echo "# Test Redis connectivity (via Kuma mesh):"
echo "kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- nc -zv redis.kuma-demo.svc.6379.mesh 80"
echo ""
echo ""
echo -e "${GREEN}[INFO]${NC} Debugging commands:"
echo "# Check if .mesh domain is properly configured:"
echo "kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c demo-app -- nslookup demo-app.kuma-demo.svc.5000.mesh"
echo ""
echo "# Check Kuma dataplane proxy status:"
echo "kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c kuma-sidecar -- wget -q -O - http://localhost:9901/stats"
echo ""
echo "# Verify Envoy admin interface:"
echo "kubectl --context k3d-member-1 exec -n kuma-demo $DEMO_POD_ZONE1 -c kuma-sidecar -- wget -q -O - http://localhost:9901/clusters"