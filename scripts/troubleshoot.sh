#!/bin/bash

ECHO_PREFIX="🔍 "
echo "${ECHO_PREFIX}Starting Troubleshooting..."

# 1. Check Docker Port Bindings
echo ""
echo "${ECHO_PREFIX}Checking Docker Port Bindings (Host -> Kind):"
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep guestbook
echo ""
echo "${ECHO_PREFIX}Checking Host Port 80/443 usage:"
sudo lsof -i :80 || echo "Port 80 free or usage hidden"
sudo lsof -i :443 || echo "Port 443 free or usage hidden"

# Check if Kind container failed to start routing
if docker ps | grep guestbook-control-plane | grep -q "0.0.0.0:80->80/tcp"; then
    echo "✅ Kind is mapped to Host Port 80."
else
    echo "❌ Kind is NOT listening on Host Port 80."
    echo "   Reason: Port might be taken by another service (like nginx/apache/k3s)."
    echo "   If so, we need to move Kind to a different port (e.g., 8081)."
fi

# 2. Check Ingress Status
echo ""
echo "${ECHO_PREFIX}Checking Kubernetes Ingress:"
kubectl get ingress -n guestbook
kubectl describe ingress guestbook-ingress -n guestbook | grep -E "Message|Events"

# 3. Check Certificates
echo ""
echo "${ECHO_PREFIX}Checking SSL Certificates:"
kubectl get certificate -n guestbook
kubectl get certificaterequest -n guestbook
kubectl get order -n guestbook

# 4. Check Local Curl
echo ""
echo "${ECHO_PREFIX}Testing Local Connectivity (curl localhost):"
curl -I -k http://localhost 2>&1 | head -n 5

echo ""
echo "${ECHO_PREFIX}Troubleshooting complete. Share this output."
