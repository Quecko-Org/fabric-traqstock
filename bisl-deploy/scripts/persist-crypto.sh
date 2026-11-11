#!/usr/bin/env bash
#
# Copy Fabric organizations/ to a durable path and keep the live path in sync.
# Prevents GitHub Actions / workspace cleans from deleting peer bind-mount certs.
#
# Usage:
#   ./scripts/persist-crypto.sh              # save live → persist
#   ./scripts/persist-crypto.sh restore      # restore persist → live if live missing
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

MODE="${1:-save}"
LIVE="${BISL_CRYPTO_LIVE}"

# Prefer durable system path on servers; fall back to home for local Mac/dev.
resolve_persist_path() {
  if [[ -n "${BISL_CRYPTO_PERSIST:-}" && "${BISL_CRYPTO_PERSIST}" != "/var/lib/bisl/organizations" ]]; then
    echo "${BISL_CRYPTO_PERSIST}"
    return
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "/var/lib/bisl/organizations"
    return
  fi
  if [[ -d /var/lib/bisl/organizations ]]; then
    echo "/var/lib/bisl/organizations"
    return
  fi
  if mkdir -p /var/lib/bisl/organizations 2>/dev/null; then
    echo "/var/lib/bisl/organizations"
    return
  fi
  echo "${HOME}/.bisl/organizations"
}
PERSIST="$(resolve_persist_path)"

admin_ok() {
  local root="$1"
  [[ -d "${root}/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore" ]]
}

save_crypto() {
  if ! admin_ok "${LIVE}"; then
    echo "Live crypto incomplete: ${LIVE}"
    echo "Start Fabric with -ca first, or run: $0 restore"
    return 1
  fi

  echo "==> Persisting crypto"
  echo "    From: ${LIVE}"
  echo "    To:   ${PERSIST}"

  mkdir -p "$(dirname "${PERSIST}")"
  rsync -a --delete "${LIVE}/" "${PERSIST}/"
  echo "Crypto saved to ${PERSIST}"
}

restore_crypto() {
  if admin_ok "${LIVE}"; then
    echo "Live crypto already present: ${LIVE}"
    return 0
  fi

  if ! admin_ok "${PERSIST}"; then
    echo "No durable crypto at ${PERSIST} and live path missing"
    return 1
  fi

  echo "==> Restoring crypto"
  echo "    From: ${PERSIST}"
  echo "    To:   ${LIVE}"

  mkdir -p "${LIVE}"
  rsync -a "${PERSIST}/" "${LIVE}/"
  echo "Crypto restored to ${LIVE}"
}

case "${MODE}" in
  save) save_crypto ;;
  restore) restore_crypto ;;
  *)
    echo "Usage: $0 [save|restore]"
    exit 1
    ;;
esac
