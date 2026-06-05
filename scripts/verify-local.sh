#!/usr/bin/env bash
# Local verification: same linux/amd64 build as CI / NAS target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE=n8n-exif:local bash "${SCRIPT_DIR}/verify.sh"

echo
echo "Run n8n locally via amd64 emulation (Execute Command node enabled):"
echo "  docker run -it --rm -p 5678:5678 \\"
echo "    --platform linux/amd64 \\"
echo "    -e 'NODES_EXCLUDE=[]' \\"
echo "    -v n8n_data:/home/node/.n8n \\"
echo "    n8n-exif:local"
