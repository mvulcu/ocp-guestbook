#!/bin/bash
set -e

# Configuration
CLUSTER_NAME="guestbook"
NAMESPACE="guestbook"

echo "🚀 Starting deployment to Kind cluster '$CLUSTER_NAME'..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo >&2 "❌ Docker is required but not installed. Aborting."; exit 1; }
command -v kind >/dev/null 2>&1 || { echo >&2 "❌ Kind is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "❌ Kubectl is required but not installed. Aborting."; exit 1; }

# 1. Create Cluster if not exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "ℹ️  Cluster '$CLUSTER_NAME' already exists."
else
    echo "📦 Creating Kind cluster..."
    kind create cluster --name "$CLUSTER_NAME"
fi

# 2. Check for GHCR Secret
if ! kubectl get secret ghcr-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "⚠️  Secret 'ghcr-secret' not found in namespace '$NAMESPACE'."
    echo "   You must create it to pull images from GHCR."
    echo "   Run: kubectl create secret docker-registry ghcr-secret -n $NAMESPACE --docker-server=ghcr.io --docker-username=<USER> --docker-password=<TOKEN>"
    # We don't exit here to allow update if secret exists but just wasn't found in this check or handled externally
fi

# 3. (Skipped) Build & Load - We use GHCR now
echo "ℹ️  Skipping local build/load. Using images from GHCR."

# 4. Apply Manifests
echo "📄 Applying Kubernetes manifests..."
kubectl apply -f k8s/kind/

# 5. Force Restart (to pull new images)
echo "🔄 Restarting deployments to pull latest images..."
kubectl rollout restart deployment/backend -n "$NAMESPACE"
kubectl rollout restart deployment/frontend -n "$NAMESPACE"

# 6. Wait for Rollout
echo "⏳ Waiting for deployments to be ready..."
# Wait for pods to be created first
sleep 5
kubectl rollout status deployment/postgres -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/redis -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=120s

echo "✅ Deployment complete!"
echo ""
echo "👉 To access the application, run:"
echo "   kubectl port-forward svc/frontend 8080:80 -n $NAMESPACE --address 0.0.0.0"
echo ""
