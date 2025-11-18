FROM nginx:alpine

RUN rm -rf /etc/nginx/nginx.conf /etc/nginx/conf.d/*

RUN chmod -R 777 /var/cache/nginx /var/log/nginx /var/run && \
    chown -R 101:101 /usr/share/nginx/html

COPY index.html /usr/share/nginx/html/index.html


COPY styles.css /usr/share/nginx/html/styles.css

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080

USER 101

CMD ["nginx", "-g", "daemon off;"]
