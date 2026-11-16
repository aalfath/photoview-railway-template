# PhotoView for Railway: the official image, plus rclone (WebDAV photo uploads at /webdav)
# and Caddy (one public port). All three are pinned by version and digest.
FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy
FROM rclone/rclone:1.76.0@sha256:7cbeec24a44f206067597c0368be4de90ae19a64d5113c7d1938bd737a81e466 AS rclone

FROM photoview/photoview:2.4.0@sha256:31c0c4fdd03856b8738cc89aede297f035d5a4e2dfa2c16763045e817e8e5b05

# The start script prepares the volume as root, then drops to the image's
# photoview user (uid 999) for every process.
USER root

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY Caddyfile /etc/photoview-railway/Caddyfile
COPY start.sh /usr/local/bin/photoview-railway-start
RUN chmod 0755 /usr/local/bin/photoview-railway-start /usr/local/bin/caddy /usr/local/bin/rclone

ENV PHOTOVIEW_DATABASE_DRIVER=postgres \
    PHOTOVIEW_LISTEN_IP=127.0.0.1 \
    PHOTOVIEW_LISTEN_PORT=8081 \
    PHOTOVIEW_MEDIA_CACHE=/data/cache \
    DATA_DIR=/data \
    PHOTOS_DIR=/data/photos

EXPOSE 8080

HEALTHCHECK --interval=60s --timeout=10s CMD curl -fsS http://127.0.0.1:${PORT:-8080}/ >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/photoview-railway-start"]
