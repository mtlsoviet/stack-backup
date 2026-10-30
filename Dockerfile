FROM alpine:3.22

RUN apk add --no-cache restic mariadb-client sqlite tzdata

COPY --chmod=755 backup.sh /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/backup.sh"]
