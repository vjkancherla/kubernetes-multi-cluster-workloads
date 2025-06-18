#!/bin/bash

set -e

echo "🔥 Starting Kuma Multi-Zone Teardown..."

# Function to check if cluster exists
cluster_exists() {
    k3d cluster list | grep -q "^$1 "
}

# Function to safely delete cluster
safe_delete_cluster() {
    local cluster_name=$1
    echo "🗑️  Deleting cluster: $cluster_name"
    if cluster_exists "$cluster_name"; then
        k3d cluster delete "$cluster_name" || echo "⚠️  Failed to delete $cluster_name, continuing..."
    else
        echo "ℹ️  Cluster $cluster_name doesn't exist, skipping..."
    fi
}

# Stop any running port-forwards
echo "🛑 Stopping any running port-forwards..."
pkill -f "kubectl.*port-forward" 2>/dev/null || true
pkill -f "kumactl.*install.*control-plane" 2>/dev/null || true

# Delete all k3d clusters
echo "🗑️  Deleting all k3d clusters..."
safe_delete_cluster "control-plane"
safe_delete_cluster "member-1" 
safe_delete_cluster "member-2"

# Clean up any remaining k3d resources
echo "🧹 Cleaning up remaining k3d resources..."
docker ps -a --filter "label=app=k3d" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" 2>/dev/null || true
docker rm -f $(docker ps -a --filter "label=app=k3d" -q) 2>/dev/null || true

# Clean up k3d networks
echo "🌐 Cleaning up k3d networks..."
docker network ls --filter "name=k3d" --format "table {{.ID}}\t{{.Name}}" 2>/dev/null || true
docker network rm $(docker network ls --filter "name=k3d" -q) 2>/dev/null || true

# Clean up kubectl contexts
echo "🔧 Cleaning up kubectl contexts..."
kubectl config delete-context k3d-control-plane 2>/dev/null || true
kubectl config delete-context k3d-member-1 2>/dev/null || true
kubectl config delete-context k3d-member-2 2>/dev/null || true

# Clean up kubectl clusters
echo "🔧 Cleaning up kubectl clusters..."
kubectl config delete-cluster k3d-control-plane 2>/dev/null || true
kubectl config delete-cluster k3d-member-1 2>/dev/null || true
kubectl config delete-cluster k3d-member-2 2>/dev/null || true

# Clean up kubectl users
echo "🔧 Cleaning up kubectl users..."
kubectl config delete-user admin@k3d-control-plane 2>/dev/null || true
kubectl config delete-user admin@k3d-member-1 2>/dev/null || true
kubectl config delete-user admin@k3d-member-2 2>/dev/null || true

# Clean up any Kuma-related Docker volumes
echo "💾 Cleaning up Docker volumes..."
docker volume ls --filter "name=k3d" --format "table {{.Name}}" 2>/dev/null || true
docker volume rm $(docker volume ls --filter "name=k3d" -q) 2>/dev/null || true

# Clean up any lingering containers
echo "🐳 Cleaning up any lingering containers..."
docker ps -a --filter "name=k3d" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" 2>/dev/null || true
docker rm -f $(docker ps -a --filter "name=k3d" -q) 2>/dev/null || true

# Remove any temporary files (if any were created)
echo "📁 Cleaning up temporary files..."
rm -f /tmp/kuma-* 2>/dev/null || true
rm -f /tmp/k3d-* 2>/dev/null || true

# Verify cleanup
echo ""
echo "🔍 Verification - Checking remaining resources..."
echo ""

echo "📊 K3d clusters:"
k3d cluster list || echo "No clusters found"

echo ""
echo "📊 Docker containers with k3d label:"
docker ps -a --filter "label=app=k3d" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" 2>/dev/null || echo "No k3d containers found"

echo ""
echo "📊 Docker networks with k3d name:"
docker network ls --filter "name=k3d" --format "table {{.ID}}\t{{.Name}}" 2>/dev/null || echo "No k3d networks found"

echo ""
echo "📊 Docker volumes with k3d name:"
docker volume ls --filter "name=k3d" --format "table {{.Name}}" 2>/dev/null || echo "No k3d volumes found"

echo ""
echo "📊 Kubectl contexts:"
kubectl config get-contexts | grep k3d || echo "No k3d contexts found"

echo ""
echo "✅ Teardown complete!"
echo ""
echo "🔄 To start fresh, you can now run the setup script again."
echo "💡 If you want to completely reset Docker, you can also run:"
echo "   docker system prune -a --volumes"
echo "   (⚠️  Warning: This will remove ALL unused Docker resources, not just k3d)"


echo ""
echo "🎉 All done! Your system is clean."