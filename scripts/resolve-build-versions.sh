#!/usr/bin/env bash
# Resolve N8N_VERSION and ALPINE_VERSION from the published n8n image manifest
# (no layer download). docker build pulls images once during the build stage.
# Defaults to n8nio/n8n:latest on Docker Hub.
#
# Usage:
#   eval "$(bash ./scripts/resolve-build-versions.sh --export)"
#   ./scripts/verify-local.sh
set -euo pipefail

N8N_REGISTRY_IMAGE="${N8N_REGISTRY_IMAGE:-n8nio/n8n}"
RESOLVE_PLATFORM="${RESOLVE_PLATFORM:-linux/amd64}"
RESOLVED_REGISTRY_IMAGE=""

resolve_image_ref() {
  local registry="$1"
  if [ -n "${N8N_VERSION:-}" ] && [ "${N8N_VERSION}" != "latest" ]; then
    printf '%s:%s' "${registry}" "${N8N_VERSION}"
  else
    printf '%s:latest' "${registry}"
  fi
}

platform_image_ref() {
  local image_ref="$1"
  local os_name="${RESOLVE_PLATFORM%%/*}"
  local arch="${RESOLVE_PLATFORM##*/}"

  docker buildx imagetools inspect "${image_ref}" --raw | python3 -c "
import json, sys

data = json.load(sys.stdin)
if 'manifests' not in data:
    sys.exit(0)

os_name, arch = sys.argv[1], sys.argv[2]
for manifest in data.get('manifests', []):
    platform = manifest.get('platform') or {}
    if platform.get('os') == os_name and platform.get('architecture') == arch:
        print(manifest['digest'])
        sys.exit(0)

sys.exit(1)
" "${os_name}" "${arch}"
}

read_labels() {
  local image_ref="$1"
  docker buildx imagetools inspect --format '{{json .}}' "${image_ref}" | python3 -c "
import json, sys

data = json.load(sys.stdin)
labels = data.get('image', {}).get('config', {}).get('Labels', {})
print(labels.get('org.opencontainers.image.version', ''))
print(labels.get('com.docker.dhi.distro', ''))
"
}

resolve_from_manifest() {
  local image_ref="$1"
  local registry_image="$2"
  local platform_ref="${image_ref}"
  local digest=""
  local label_lines
  local alpine_distro

  echo "Inspecting ${image_ref} (${RESOLVE_PLATFORM})..." >&2

  if digest="$(platform_image_ref "${image_ref}" 2>/dev/null)" && [ -n "${digest}" ]; then
    platform_ref="${image_ref}@${digest}"
  fi

  if ! label_lines="$(read_labels "${platform_ref}" 2>/dev/null)"; then
    return 1
  fi

  N8N_VERSION="$(printf '%s\n' "${label_lines}" | sed -n '1p')"
  alpine_distro="$(printf '%s\n' "${label_lines}" | sed -n '2p')"

  if [ -n "${alpine_distro}" ] && [ "${alpine_distro}" != "<no value>" ]; then
    ALPINE_VERSION="${alpine_distro#alpine-}"
  elif [ -n "${N8N_VERSION}" ] && [ "${N8N_VERSION}" != "<no value>" ]; then
    echo "Alpine label missing on ${platform_ref}; pulling image to read /etc/alpine-release..." >&2
    docker pull --platform "${RESOLVE_PLATFORM}" "${image_ref}" >&2
    local alpine_release
    alpine_release="$(docker run --rm --platform "${RESOLVE_PLATFORM}" --entrypoint cat "${image_ref}" /etc/alpine-release)"
    ALPINE_VERSION="$(python3 -c "print('.'.join('${alpine_release}'.strip().split('.')[:2]))")"
  fi

  if [ -z "${N8N_VERSION}" ] || [ "${N8N_VERSION}" = "<no value>" ]; then
    return 1
  fi

  if [ -z "${ALPINE_VERSION}" ]; then
    return 1
  fi

  RESOLVED_REGISTRY_IMAGE="${registry_image}"
  return 0
}

IMAGE_REF="$(resolve_image_ref "${N8N_REGISTRY_IMAGE}")"
if ! resolve_from_manifest "${IMAGE_REF}" "${N8N_REGISTRY_IMAGE}"; then
  echo "Could not resolve n8n/Alpine versions from ${N8N_REGISTRY_IMAGE}" >&2
  exit 1
fi

echo "Resolved from ${IMAGE_REF}: n8n ${N8N_VERSION}, Alpine ${ALPINE_VERSION}" >&2

print_build_arg_file() {
  printf 'RESOLVED_BY_SCRIPT=true\n'
  printf 'N8N_REGISTRY_IMAGE=%s\n' "${RESOLVED_REGISTRY_IMAGE}"
  printf 'N8N_VERSION=%s\n' "${N8N_VERSION}"
  printf 'ALPINE_VERSION=%s\n' "${ALPINE_VERSION}"
}

case "${1:-}" in
  --export)
    printf 'export N8N_REGISTRY_IMAGE=%q\n' "${RESOLVED_REGISTRY_IMAGE}"
    printf 'export N8N_VERSION=%q\n' "${N8N_VERSION}"
    printf 'export ALPINE_VERSION=%q\n' "${ALPINE_VERSION}"
    ;;
  --build-arg-file)
    print_build_arg_file
    ;;
  *)
    export N8N_REGISTRY_IMAGE="${RESOLVED_REGISTRY_IMAGE}" N8N_VERSION ALPINE_VERSION
    ;;
esac
