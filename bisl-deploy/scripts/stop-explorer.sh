#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -d "${SCRIPT_DIR}/../explorer" && -f "${SCRIPT_DIR}/../explorer/docker-compose.yaml" ]]; then
  EXPLORER_DIR="$(cd "${SCRIPT_DIR}/../explorer" && pwd)"
else
  echo "Explorer folder not found"
  exit 1
fi

cd "${EXPLORER_DIR}"
docker compose down -v
echo "Explorer stopped (volumes removed)"
