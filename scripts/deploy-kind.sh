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

# 2. Build Images (Local VPS scenario)
echo "🔨 Building Docker images..."
docker build -t guestbook-backend:local ./backend
docker build -t guestbook-frontend:local ./frontend

# 3. Load Images into Kind
echo "🚚 Loading images into Kind..."
kind load docker-image guestbook-backend:local --name "$CLUSTER_NAME"
kind load docker-image guestbook-frontend:local --name "$CLUSTER_NAME"

# 4. Apply Manifests
echo "📄 Applying Kubernetes manifests..."
kubectl apply -f k8s/kind/

# 5. Wait for Rollout
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
