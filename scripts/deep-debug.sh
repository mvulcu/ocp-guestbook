#!/bin/bash
ECHO_PREFIX="🕵️  "
echo "${ECHO_PREFIX}Deep Debugging Connectivity..."

# 1. Check Pod Status Detailed
echo ""
echo "${ECHO_PREFIX}1. Ingress Pod Status:"
kubectl get pods -n ingress-nginx -o wide

# 2. Check Internal Kind Node Ports (Is something listening INSIDE the node?)
echo ""
echo "${ECHO_PREFIX}2. Listening Ports INSIDE Kind Node (guestbook-control-plane):"
docker exec guestbook-control-plane netstat -tulpn 2>/dev/null | grep -E ":80|:443" || echo "❌ Nothing listening on 80/443 inside the node!"

# 3. Check Docker Proxy on Host
echo ""
echo "${ECHO_PREFIX}3. Docker Proxy on Host:"
sudo netstat -tulpn | grep docker-proxy

# 4. Connectivity Tests
echo ""
echo "${ECHO_PREFIX}4. Curl Tests:"
echo "👉 Trying 127.0.0.1 (IPv4)..."
curl -v -4 http://127.0.0.1 2>&1 | head -n 5

echo ""
echo "👉 Trying Public IP (if available)..."
PUBLIC_IP=$(curl -s ifconfig.me)
echo "   IP: $PUBLIC_IP"
curl -v http://$PUBLIC_IP 2>&1 | head -n 5
