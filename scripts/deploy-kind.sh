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
    echo "⚠️  If port mappings (80/443) are missing, you must run 'sh scripts/destroy-kind.sh' first!"
else
    echo "📦 Creating Kind cluster with NodePorts..."
    # Config needed for 80/443 mapping
    if [ ! -f kind-config.yaml ]; then
        echo "❌ kind-config.yaml missing! Cannot map ports."
        exit 1
    fi
    kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml
fi

# 1.1 Install Nginx Ingress Controller
# 1.1 Install Nginx Ingress Controller
echo "🌐 Checking Nginx Ingress Controller..."
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  echo "Installing Nginx Ingress Controller..."
  # Download manifest
  curl -L https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml -o ingress.yaml
  # Patch: Remove hostPort to avoid conflicts with existing K3s/LB on VPS (User Confirmed Fix)
  sed -i '/hostPort:/d' ingress.yaml
  # Apply
  kubectl apply -f ingress.yaml
  rm ingress.yaml

  echo "⏳ Waiting for Ingress Controller to be ready..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s
else
  echo "✅ Ingress Controller already installed. Skipping."
fi

# 1.2 Install Cert-Manager
echo "🔒 Checking Cert-Manager..."
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  echo "Installing Cert-Manager..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
  echo "⏳ Waiting for Cert-Manager..."
  kubectl wait --namespace cert-manager \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s
else
   echo "✅ Cert-Manager already installed. Skipping."
fi

# 2. Check for GHCR Secret
if ! kubectl get secret ghcr-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    # Create namespace if check fails (likely first run)
    kubectl create namespace "$NAMESPACE" || true

    echo "⚠️  Secret 'ghcr-secret' not found in namespace '$NAMESPACE'."
    echo "   You must create it to pull images from GHCR."
    echo "   Run: kubectl create secret docker-registry ghcr-secret -n $NAMESPACE --docker-server=ghcr.io --docker-username=<USER> --docker-password=<TOKEN>"
    # We don't exit here to allow update if secret exists but just wasn't found in this check or handled externally
fi

# 3. Apply Manifests
echo "📄 Applying Kubernetes manifests..."
# Ensure Issuer is applied
kubectl apply -f k8s/kind/

# 4. Force Restart (to pull new images)
echo "🔄 Restarting deployments to pull latest images..."
kubectl rollout restart deployment/backend -n "$NAMESPACE"
kubectl rollout restart deployment/frontend -n "$NAMESPACE"

# 5. Wait for Rollout
echo "⏳ Waiting for deployments to be ready..."
sleep 5
kubectl rollout status deployment/postgres -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/redis -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout=120s
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=120s

echo "✅ Deployment complete!"
echo "🌍 App should be available at https://guestbook.cicd.cachefly.site"
