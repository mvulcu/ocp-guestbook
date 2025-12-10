#!/bin/bash

ECHO_PREFIX="🔍 "
echo "${ECHO_PREFIX}Starting Troubleshooting..."

# 1. Check Docker Port Bindings
echo ""
echo "${ECHO_PREFIX}Checking Docker Port Bindings (Host -> Kind):"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep guestbook-control-plane
if docker ps | grep guestbook-control-plane | grep -q "0.0.0.0:80->80/tcp"; then
    echo "✅ Port 80 is mapped correctly."
else
    echo "❌ Port 80 is NOT mapped! Did you run 'destroy-kind.sh' before deploying with new config?"
fi
if docker ps | grep guestbook-control-plane | grep -q "0.0.0.0:443->443/tcp"; then
    echo "✅ Port 443 is mapped correctly."
else
    echo "❌ Port 443 is NOT mapped!"
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
