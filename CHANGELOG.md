# Changelog

## 2.4.0-r1 (2026-11-16)

First version of the template.

- PhotoView 2.4.0 (`photoview/photoview:2.4.0@sha256:31c0c4fdd03856b8738cc89aede297f035d5a4e2dfa2c16763045e817e8e5b05`) with Railway Postgres.
- The start script finishes PhotoView's initial setup with `ADMIN_USERNAME` / `ADMIN_PASSWORD` before the public port opens, so the setup wizard is never exposed.
- WebDAV upload at `/webdav` (rclone 1.76.0) and Caddy 2.11.9 as the single public listener.
- One volume at `/data` (photos in `/data/photos`, cache in `/data/cache`).
