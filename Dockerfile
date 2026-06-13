# syntax=docker/dockerfile:1
#
# N8N_VERSION, ALPINE_VERSION, and N8N_REGISTRY_IMAGE are resolved by
# scripts/resolve-build-versions.sh from the published n8n manifest (no layer pull).
# docker build pulls base images once. Do not build without that script.
#
#   ./scripts/verify-local.sh
#
#   bash scripts/resolve-build-versions.sh --build-arg-file | while IFS= read -r arg; do
#     [ -n "$arg" ] && BUILD_ARGS+=(--build-arg "$arg")
#   done
#   docker build "${BUILD_ARGS[@]}" -t n8n-exif .
#
# Linter-only defaults below; the script always overrides them via --build-arg-file.
ARG RESOLVED_BY_SCRIPT=false
ARG N8N_REGISTRY_IMAGE=n8nio/n8n
ARG N8N_VERSION=latest
ARG ALPINE_VERSION=3.22

FROM alpine:${ALPINE_VERSION} AS apk-donor

ARG N8N_REGISTRY_IMAGE
ARG N8N_VERSION
ARG RESOLVED_BY_SCRIPT
FROM ${N8N_REGISTRY_IMAGE}:${N8N_VERSION}

ARG RESOLVED_BY_SCRIPT
RUN if [ "${RESOLVED_BY_SCRIPT}" != "true" ]; then \
  echo "Build via scripts/resolve-build-versions.sh (see Dockerfile header)." >&2; \
  exit 1; \
  fi

COPY --from=apk-donor /sbin/apk /sbin/apk
COPY --from=apk-donor /usr/lib/libapk.so* /usr/lib/

USER root
RUN apk add --no-cache \
  exiftool \
  chromium \
  && npm install -g --omit=dev --no-audit --no-fund city-timezones tz-lookup

ENV NODE_FUNCTION_ALLOW_EXTERNAL=city-timezones,tz-lookup
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
  PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

USER node
