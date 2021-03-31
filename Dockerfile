FROM --platform=$TARGETPLATFORM nginx
COPY _site /usr/share/nginx/html
