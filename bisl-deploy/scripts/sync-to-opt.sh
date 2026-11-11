#!/usr/bin/env bash
#
# Sync checkout bisl-deploy → /opt/bisl-deploy.
# Preserves crypto, wallet, .env, and host-native fabric binaries.
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

SUDO=()
if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
fi

echo "==> Syncing deploy code"
echo "    From: ${SRC}"
echo "    To:   ${DST}"

"${SUDO[@]}" mkdir -p "${DST}"

RSYNC=(rsync -a --delete)
if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is required on the runner (sudo apt-get install -y rsync)" >&2
  exit 1
fi

# Do not overwrite runtime/host-managed paths
"${SUDO[@]}" "${RSYNC[@]}" \
  --exclude 'fabric/bin/' \
  --exclude 'fabric/config/' \
  --exclude 'fabric/test-network/bin/' \
  --exclude 'fabric/test-network/organizations/' \
  --exclude 'fabric/test-network/channel-artifacts/' \
  --exclude 'rpc/wallet/' \
  --exclude 'rpc/node_modules/' \
  --exclude 'rpc/.env' \
  --exclude 'explorer/.env' \
  --exclude 'chaincode/node_modules/' \
  "${SRC}/" "${DST}/"

"${SUDO[@]}" chmod +x "${DST}/scripts/"*.sh || true
# Runner must own the tree for wallet setup / network scripts
"${SUDO[@]}" chown -R "$(id -u):$(id -g)" "${DST}"

echo "Synced to ${DST}"
ls -la "${DST}/scripts" | head
