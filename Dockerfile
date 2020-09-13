FROM nginx
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx-conf /etc/nginx/conf.d
COPY content /usr/share/nginx/html

EXPOSE 80/tcp
