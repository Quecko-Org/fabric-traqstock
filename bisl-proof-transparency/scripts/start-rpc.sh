#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

RPC_DIR="${BISL_RPC_DIR}"

cd "${RPC_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -f .env.vps ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env.vps
  set +a
fi

export FABRIC_ROOT="${FABRIC_ROOT:-${BISL_FABRIC_DIR}}"

echo "Starting BISL RPC on port ${PORT:-4000}"
echo "  FABRIC_ROOT=${FABRIC_ROOT}"
echo "  RPC_DIR=${RPC_DIR}"
exec node app.js
