FROM alpine

RUN apk add --no-cache \
    pdns \
    pdns-backend-sqlite3 \
    sqlite \
    tini

RUN mkdir -p /data /etc/powerdns

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/sbin/tini","--","/entrypoint.sh"]
