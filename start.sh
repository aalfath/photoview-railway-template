#!/bin/bash
# Start script for the PhotoView Railway template.
# 1. prepare the volume, 2. start PhotoView on localhost, 3. finish PhotoView's
# initial setup with ADMIN_USERNAME / ADMIN_PASSWORD (so the setup wizard is never
# open to the internet), 4. start the WebDAV upload server, 5. open the public port with Caddy.
set -euo pipefail

log() { echo "[photoview-railway] $*"; }

DATA_DIR="${DATA_DIR:-/data}"
PHOTOS_DIR="${PHOTOS_DIR:-$DATA_DIR/photos}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
PERIODIC_SCAN_SECONDS="${PERIODIC_SCAN_SECONDS:-900}"
export PORT="${PORT:-8080}"
export HOME=/home/photoview
RUN_AS=(setpriv --reuid=999 --regid=999 --init-groups)

: "${PHOTOVIEW_POSTGRES_URL:?PHOTOVIEW_POSTGRES_URL is not set (it should reference the Postgres service)}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD is not set}"
if [ "${#ADMIN_PASSWORD}" -lt 12 ]; then
  log "ADMIN_PASSWORD must be at least 12 characters"; exit 1
fi
if ! [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._@-]+$ ]]; then
  log "ADMIN_USERNAME may only contain letters, digits and . _ @ -"; exit 1
fi
if ! [[ "$ADMIN_PASSWORD" =~ ^[A-Za-z0-9._~@%+=-]+$ ]]; then
  log "ADMIN_PASSWORD may only contain letters, digits and . _ ~ @ % + = -"; exit 1
fi

# Volume layout (Railway mounts volumes as root)
mkdir -p "$DATA_DIR" "$PHOTOS_DIR" "$PHOTOVIEW_MEDIA_CACHE"
chown 999:999 "$DATA_DIR" "$PHOTOS_DIR" "$PHOTOVIEW_MEDIA_CACHE"

pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; wait || true; }
trap cleanup TERM INT

log "starting PhotoView on 127.0.0.1:${PHOTOVIEW_LISTEN_PORT}"
cd /home/photoview
"${RUN_AS[@]}" /app/photoview &
pids+=("$!")

gql() {
  curl -fsS -m 20 "http://127.0.0.1:${PHOTOVIEW_LISTEN_PORT}/api/graphql" \
    -H 'Content-Type: application/json' ${2:+-H "Cookie: auth-token=$2"} --data-raw "$1"
}

log "waiting for PhotoView"
for i in $(seq 1 180); do
  if out=$(gql '{"query":"query { siteInfo { initialSetup } }"}' 2>/dev/null); then break; fi
  if ! kill -0 "${pids[0]}" 2>/dev/null; then log "PhotoView exited during startup"; exit 1; fi
  sleep 2
done
[ -n "${out:-}" ] || { log "PhotoView did not answer in time"; exit 1; }

if echo "$out" | grep -q '"initialSetup":true'; then
  log "running PhotoView's initial setup for user '$ADMIN_USERNAME' (photo folder $PHOTOS_DIR)"
  q=$(printf '{"query":"mutation($u:String!,$p:String!,$r:String!){ initialSetupWizard(username:$u,password:$p,rootPath:$r){ success status token } }","variables":{"u":"%s","p":"%s","r":"%s"}}' \
    "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$PHOTOS_DIR")
  res=$(gql "$q")
  if ! echo "$res" | grep -q '"success":true'; then
    log "initial setup failed: $(echo "$res" | sed 's/"token":"[^"]*"/"token":"***"/')"; exit 1
  fi
  token=$(echo "$res" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  if [ "$PERIODIC_SCAN_SECONDS" -gt 0 ] 2>/dev/null && [ -n "$token" ]; then
    if gql "{\"query\":\"mutation { setPeriodicScanInterval(interval: ${PERIODIC_SCAN_SECONDS}) }\"}" "$token" 2>/dev/null \
        | grep -q '"setPeriodicScanInterval":'"${PERIODIC_SCAN_SECONDS}"; then
      log "periodic scan set to every ${PERIODIC_SCAN_SECONDS}s"
    else
      log "could not set the periodic scan interval (set it in PhotoView's Settings)"
    fi
  fi
  log "initial setup done"
else
  log "PhotoView is already set up"
fi

# WebDAV (rclone): upload and manage the photo folder at /webdav, same admin login.
# Credentials go through the environment, not the command line.
log "starting WebDAV on 127.0.0.1:8082 (/webdav)"
RCLONE_USER="$ADMIN_USERNAME" RCLONE_PASS="$ADMIN_PASSWORD" RCLONE_CONFIG=/dev/null \
  "${RUN_AS[@]}" /usr/local/bin/rclone serve webdav "$PHOTOS_DIR" \
  --addr 127.0.0.1:8082 --baseurl /webdav --log-level NOTICE &
pids+=("$!")

log "starting Caddy on :${PORT}"
"${RUN_AS[@]}" /usr/local/bin/caddy run --config /etc/photoview-railway/Caddyfile --adapter caddyfile &
pids+=("$!")

# If any process exits, stop the others so Railway restarts the container.
set +e
wait -n "${pids[@]}"
code=$?
log "a process exited (code $code), stopping"
cleanup
exit "$code"
