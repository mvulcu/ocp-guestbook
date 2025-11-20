FROM nginx:alpine

RUN rm -rf /etc/nginx/nginx.conf /etc/nginx/conf.d/*

RUN chmod -R 777 /var/cache/nginx /var/log/nginx /var/run && \
    chown -R 101:101 /usr/share/nginx/html

COPY index.html /usr/share/nginx/html/index.html


COPY styles.css /usr/share/nginx/html/styles.css
COPY script.js /usr/share/nginx/html/script.js
COPY success.png /usr/share/nginx/html/success.png
COPY error.png /usr/share/nginx/html/error.png
COPY update.png /usr/share/nginx/html/update.png
COPY delete.png /usr/share/nginx/html/delete.png
COPY success.mp3 /usr/share/nginx/html/success.mp3
COPY error.mp3 /usr/share/nginx/html/error.mp3
COPY update.mp3 /usr/share/nginx/html/update.mp3
COPY delete.mp3 /usr/share/nginx/html/delete.mp3
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
