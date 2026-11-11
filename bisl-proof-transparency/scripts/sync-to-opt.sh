#!/usr/bin/env bash
#
# Sync checkout bisl-deploy → durable /opt/bisl-deploy WITHOUT wiping crypto, wallet, or .env.
# Run on the EC2 self-hosted runner before deploy.
#
set -euo pipefail

SRC="${1:-}"
DST="${2:-/opt/bisl-deploy}"

if [[ -z "${SRC}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

if [[ ! -d "${SRC}/fabric/test-network" ]]; then
  echo "Source is not a bisl-deploy tree: ${SRC}" >&2
  exit 1
fi

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

echo "==> Syncing deploy code"
echo "    From: ${SRC}"
echo "    To:   ${DST}"

run_as_root mkdir -p "${DST}"

# Preserve runtime secrets / crypto / wallet across syncs
run_as_root rsync -a \
  --delete \
  --exclude 'fabric/test-network/organizations/' \
  --exclude 'fabric/test-network/channel-artifacts/' \
  --exclude 'rpc/wallet/' \
  --exclude 'rpc/node_modules/' \
  --exclude 'rpc/.env' \
  --exclude 'explorer/.env' \
  --exclude 'chaincode/node_modules/' \
  "${SRC}/" "${DST}/"

run_as_root chmod +x "${DST}/scripts/"*.sh
# Runner user needs write for wallet setup / compose
run_as_root chown -R "$(id -u):$(id -g)" \
  "${DST}/rpc" \
  "${DST}/scripts" \
  "${DST}/explorer" \
  "${DST}/chaincode" \
  "${DST}/fabric/test-network" 2>/dev/null || true

echo "Synced to ${DST}"
