#!/usr/bin/env bash
set -euo pipefail

BACKEND_IMAGE="ghcr.io/mvulcu/guestbook-backend:latest"
FRONTEND_IMAGE="ghcr.io/mvulcu/guestbook-frontend:latest"
CHART_PATH="./helm/guestbook"
MANIFEST="guestbook.yaml"

echo "=== Building backend image ==="
docker build -t "$BACKEND_IMAGE" ./backend

echo "=== Pushing backend image ==="
docker push "$BACKEND_IMAGE"

echo "=== Building frontend image ==="
docker build -t "$FRONTEND_IMAGE" ./frontend

echo "=== Pushing frontend image ==="
docker push "$FRONTEND_IMAGE"

echo "=== Rendering Helm chart to $MANIFEST ==="
if [ -f "./values-secrets.yaml" ]; then
  echo "Using values-secrets.yaml for sensitive data"
  helm template guestbook "$CHART_PATH" -f "$CHART_PATH/values.yaml" -f "./values-secrets.yaml" > "$MANIFEST"
else
  echo "WARNING: values-secrets.yaml not found, using default values"
  helm template guestbook "$CHART_PATH" > "$MANIFEST"
fi

echo "=== Applying manifests to OpenShift ==="
oc apply -f "$MANIFEST"

echo "=== Restarting deployments ==="
oc rollout restart deploy/backend || true
oc rollout restart deploy/frontend || true
oc rollout restart deploy/prometheus || true
oc rollout restart deploy/grafana || true

echo "=== Current pods ==="
oc get pods

echo "=== Routes ==="
echo ""
echo "Frontend:"
FRONTEND_ROUTE=$(oc get route frontend -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$FRONTEND_ROUTE" ]; then
  echo "  URL: https://$FRONTEND_ROUTE"
else
  echo "  Route not found"
fi

echo ""
echo "Grafana:"
GRAFANA_ROUTE=$(oc get route grafana -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$GRAFANA_ROUTE" ]; then
  echo "  URL: https://$GRAFANA_ROUTE"
  echo "  User: admin"
  echo "  Password: (check values-secrets.yaml)"
else
  echo "  Route not found"
fi
