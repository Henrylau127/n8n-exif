#!/usr/bin/env bash
# Resolve versions from published n8n:latest manifest, build linux/amd64, verify deps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-n8n-exif:verify}"
PLATFORM="${PLATFORM:-linux/amd64}"

BUILD_ARG_FILE="$(mktemp)"
trap 'rm -f "${BUILD_ARG_FILE}"' EXIT
RESOLVE_PLATFORM="${PLATFORM}" bash "${SCRIPT_DIR}/resolve-build-versions.sh" --build-arg-file >"${BUILD_ARG_FILE}"

N8N_REGISTRY_IMAGE=""
N8N_VERSION=""
ALPINE_VERSION=""
BUILD_ARGS=()
while IFS= read -r line || [ -n "${line}" ]; do
  [ -z "${line}" ] && continue
  BUILD_ARGS+=(--build-arg "${line}")
  key="${line%%=*}"
  value="${line#*=}"
  case "${key}" in
    N8N_REGISTRY_IMAGE) N8N_REGISTRY_IMAGE="${value}" ;;
    N8N_VERSION) N8N_VERSION="${value}" ;;
    ALPINE_VERSION) ALPINE_VERSION="${value}" ;;
  esac
done <"${BUILD_ARG_FILE}"

: "${N8N_REGISTRY_IMAGE:?Failed to resolve N8N_REGISTRY_IMAGE}"
: "${N8N_VERSION:?Failed to resolve N8N_VERSION}"
: "${ALPINE_VERSION:?Failed to resolve ALPINE_VERSION}"

echo "==> Resolved ${N8N_REGISTRY_IMAGE}:${N8N_VERSION} with Alpine ${ALPINE_VERSION}"

echo "==> Build for ${PLATFORM}"
docker build \
  --platform "${PLATFORM}" \
  "${BUILD_ARGS[@]}" \
  -t "${IMAGE}" \
  "${ROOT_DIR}"

echo "==> Verify exiftool and npm packages"
docker run --rm --platform "${PLATFORM}" --entrypoint sh "${IMAGE}" -c \
  'exiftool -ver && node -e "require(\"city-timezones\"); require(\"tz-lookup\")"'

echo "Checks passed (${N8N_REGISTRY_IMAGE}:${N8N_VERSION}, Alpine ${ALPINE_VERSION})."
