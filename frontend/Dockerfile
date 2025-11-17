FROM registry.access.redhat.com/ubi10/nginx-126:10.0

# Copy our page
COPY index.html /opt/app-root/src/index.html

# Replace nginx config with our own
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080

USER 1001
