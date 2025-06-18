#!/bin/bash

# Test connectivity from Member Clusters to the Control-Plane Cluster
# Pods are launched in each of the members clusters and connectivity to
# the Control-Plane cluster's IP is verified via PING.

# Get all container IPs
echo ""
echo "=== Cluster Container IPs ==="
for cluster in control-plane member-1 member-2; do
  echo "Cluster: $cluster"
  CONTAINER_IP=$(docker inspect k3d-${cluster}-server-0 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
  echo "  Server IP: $CONTAINER_IP"
done

# Test connectivity using K8s pods
echo ""
echo "=== Testing connectivity with K8s pods ==="
CONTROL_IP=$(docker inspect k3d-control-plane-server-0 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
MEMBER1_IP=$(docker inspect k3d-member-1-server-0 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
MEMBER2_IP=$(docker inspect k3d-member-2-server-0 --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

# Clean up any existing test pods first
kubectl --context k3d-member-1 delete pod test-pod-1 --force --grace-period=0 >/dev/null 2>&1 || true
kubectl --context k3d-member-2 delete pod test-pod-2 --force --grace-period=0 >/dev/null 2>&1 || true
sleep 2

# Deploy test pods for connectivity testing (without TTY flags)
kubectl --context k3d-member-1 run test-pod-1 --image=busybox --restart=Never --command -- sleep 3600 >/dev/null 2>&1 &
kubectl --context k3d-member-2 run test-pod-2 --image=busybox --restart=Never --command -- sleep 3600 >/dev/null 2>&1 &

# Wait for background jobs
wait

# Wait for pods to be ready
echo ""
echo "Waiting for pods to be ready..."
kubectl --context k3d-member-1 wait --for=condition=Ready pod/test-pod-1 --timeout=60s >/dev/null 2>&1
kubectl --context k3d-member-2 wait --for=condition=Ready pod/test-pod-2 --timeout=60s >/dev/null 2>&1

# Test from member-1 pod to control-plane
echo ""
echo "Testing from member-1 pod to control-plane..."
kubectl --context k3d-member-1 exec test-pod-1 -- ping -c 2 $CONTROL_IP 2>/dev/null

# Test from member-2 pod to control-plane
echo ""
echo "Testing from member-2 pod to control-plane..."
kubectl --context k3d-member-2 exec test-pod-2 -- ping -c 2 $CONTROL_IP 2>/dev/null

# Test Kuma port connectivity from pods (only works AFTER Kuma has been configured)
echo ""
echo "Testing Kuma port connectivity..."
echo "Note: This test will fail if Kuma is not yet configured on the control-plane cluster"
kubectl --context k3d-member-1 exec test-pod-1 -- timeout 5 nc -zv $CONTROL_IP 5685 2>/dev/null && echo "Member-1 to Control-Plane port 5685: OK" || echo "Member-1 to Control-Plane port 5685: FAILED (expected if Kuma not configured)"
kubectl --context k3d-member-2 exec test-pod-2 -- timeout 5 nc -zv $CONTROL_IP 5685 2>/dev/null && echo "Member-2 to Control-Plane port 5685: OK" || echo "Member-2 to Control-Plane port 5685: FAILED (expected if Kuma not configured)"

# Clean up test pods
echo ""
echo "Cleaning up..."
kubectl --context k3d-member-1 delete pod test-pod-1 --force --grace-period=0 >/dev/null 2>&1 || true
kubectl --context k3d-member-2 delete pod test-pod-2 --force --grace-period=0 >/dev/null 2>&1 || true

echo ""
echo "Test completed."