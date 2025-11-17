FROM registry.access.redhat.com/ubi10/nginx-126:10.0

USER root

COPY index.html /opt/app-root/src/index.html
COPY nginx.conf /etc/nginx/nginx.conf

RUN chmod -R 777 /var/log/nginx /var/lib/nginx /run

USER 1001

EXPOSE 8080

CMD ["/usr/libexec/s2i/run"]
