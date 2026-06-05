#!/usr/bin/env bash
# Resolve the published n8n version and decide whether a new image build is needed.
# Compares against .ci/last-built-version (restored from Actions cache in CI).
#
# Usage:
#   bash ./scripts/check-build-version.sh
#   FORCE_BUILD=true bash ./scripts/check-build-version.sh
#
# Outputs (when GITHUB_OUTPUT is set):
#   build_needed, n8n_version, n8n_registry_image, alpine_version
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LAST_BUILT_FILE="${LAST_BUILT_FILE:-${ROOT_DIR}/.ci/last-built-version}"
BUILD_ARG_FILE="${BUILD_ARG_FILE:-}"
FORCE_BUILD="${FORCE_BUILD:-false}"
RESOLVE_PLATFORM="${RESOLVE_PLATFORM:-linux/amd64}"

eval "$(RESOLVE_PLATFORM="${RESOLVE_PLATFORM}" bash "${SCRIPT_DIR}/resolve-build-versions.sh" --export)"

if [ -z "${BUILD_ARG_FILE}" ]; then
  BUILD_ARG_FILE="$(mktemp)"
  trap 'rm -f "${BUILD_ARG_FILE}"' EXIT
fi

RESOLVE_PLATFORM="${RESOLVE_PLATFORM}" bash "${SCRIPT_DIR}/resolve-build-versions.sh" --build-arg-file >"${BUILD_ARG_FILE}"

LAST_N8N_VERSION=""
if [ -f "${LAST_BUILT_FILE}" ]; then
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -z "${line}" ] && continue
    key="${line%%=*}"
    value="${line#*=}"
    if [ "${key}" = "N8N_VERSION" ]; then
      LAST_N8N_VERSION="${value}"
    fi
  done <"${LAST_BUILT_FILE}"
fi

BUILD_NEEDED="true"
SKIP_REASON=""

if [ "${FORCE_BUILD}" = "true" ]; then
  SKIP_REASON="force_build enabled"
elif [ -n "${LAST_N8N_VERSION}" ] && [ "${LAST_N8N_VERSION}" = "${N8N_VERSION}" ]; then
  BUILD_NEEDED="false"
  SKIP_REASON="n8n ${N8N_VERSION} already built"
else
  if [ -n "${LAST_N8N_VERSION}" ]; then
    SKIP_REASON="n8n updated ${LAST_N8N_VERSION} -> ${N8N_VERSION}"
  else
    SKIP_REASON="no previous build recorded"
  fi
fi

echo "Resolved ${N8N_REGISTRY_IMAGE}:${N8N_VERSION} (Alpine ${ALPINE_VERSION})"
if [ -n "${LAST_N8N_VERSION}" ]; then
  echo "Last built n8n version: ${LAST_N8N_VERSION}"
else
  echo "Last built n8n version: (none)"
fi

if [ "${BUILD_NEEDED}" = "true" ]; then
  echo "Build needed: ${SKIP_REASON}"
else
  echo "Build skipped: ${SKIP_REASON}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'build_needed=%s\n' "${BUILD_NEEDED}"
    printf 'n8n_version=%s\n' "${N8N_VERSION}"
    printf 'n8n_registry_image=%s\n' "${N8N_REGISTRY_IMAGE}"
    printf 'alpine_version=%s\n' "${ALPINE_VERSION}"
    printf 'last_n8n_version=%s\n' "${LAST_N8N_VERSION}"
    printf 'skip_reason=%s\n' "${SKIP_REASON}"
    printf 'build_arg_file=%s\n' "${BUILD_ARG_FILE}"
  } >>"${GITHUB_OUTPUT}"
fi
