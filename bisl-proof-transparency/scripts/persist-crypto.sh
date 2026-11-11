#!/usr/bin/env bash
#
# Durable Fabric crypto store (survives Actions checkout wipes).
#
# Source of truth on servers: /var/lib/bisl/organizations
# Live path (peer bind mounts): <deploy>/fabric/test-network/organizations
#
# Usage:
#   ./scripts/persist-crypto.sh save
#   ./scripts/persist-crypto.sh restore
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

MODE="${1:-save}"
LIVE="${BISL_CRYPTO_LIVE}"

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

resolve_persist_path() {
  if [[ -n "${BISL_CRYPTO_PERSIST:-}" ]]; then
    echo "${BISL_CRYPTO_PERSIST}"
    return
  fi
  # Servers / CI self-hosted: always prefer durable system path
  if [[ "$(uname -s)" == "Linux" ]]; then
    echo "/var/lib/bisl/organizations"
    return
  fi
  echo "${HOME}/.bisl/organizations"
}

PERSIST="$(resolve_persist_path)"
export BISL_CRYPTO_PERSIST="${PERSIST}"

admin_ok() {
  local root="$1"
  [[ -d "${root}/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore" ]] \
    && [[ -d "${root}/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls" ]]
}

ensure_persist_dir() {
  run_as_root mkdir -p "${PERSIST}"
  # Allow ubuntu/runner to rsync without sudo next time when possible
  if [[ "$(uname -s)" == "Linux" ]]; then
    run_as_root chown -R "$(id -u):$(id -g)" /var/lib/bisl 2>/dev/null || true
  fi
}

# CA containers write fabric-ca/*/msp/keystore as root:0600; peer/orderer
# TLS material can also be root-owned after docker bind mounts. Always fix
# ownership before rsync so Actions runners can persist without exit 23.
fix_crypto_perms() {
  local root="$1"
  [[ -d "${root}" ]] || return 0
  run_as_root chown -R "$(id -u):$(id -g)" "${root}" 2>/dev/null || true
  run_as_root chmod -R a+rX "${root}" 2>/dev/null || true
  # Private keys must stay owner-readable after a+rX on dirs
  find "${root}" -type f \( -name '*_sk' -o -name 'priv_sk' -o -name 'key.pem' \) \
    -exec chmod 600 {} + 2>/dev/null || true
}

rsync_to() {
  local src="$1"
  local dst="$2"
  run_as_root mkdir -p "${dst}"
  # Prefer root rsync on Linux so root-only CA keystore files never trip exit 23
  if [[ "$(uname -s)" == "Linux" ]]; then
    run_as_root rsync -a --delete "${src}/" "${dst}/"
  elif [[ -w "${dst}" ]]; then
    rsync -a --delete "${src}/" "${dst}/"
  else
    run_as_root rsync -a --delete "${src}/" "${dst}/"
  fi
}

save_crypto() {
  if ! admin_ok "${LIVE}"; then
    echo "Live crypto incomplete: ${LIVE}"
    return 1
  fi

  echo "==> Persisting crypto"
  echo "    From: ${LIVE}"
  echo "    To:   ${PERSIST}"
  ensure_persist_dir
  fix_crypto_perms "${LIVE}"
  rsync_to "${LIVE}" "${PERSIST}"
  fix_crypto_perms "${PERSIST}"
  echo "Crypto saved to ${PERSIST}"
}

restore_crypto() {
  if admin_ok "${LIVE}"; then
    echo "Live crypto already present: ${LIVE}"
    fix_crypto_perms "${LIVE}"
    return 0
  fi

  if ! admin_ok "${PERSIST}"; then
    echo "No durable crypto at ${PERSIST}"
    return 1
  fi

  echo "==> Restoring crypto"
  echo "    From: ${PERSIST}"
  echo "    To:   ${LIVE}"
  mkdir -p "${LIVE}"
  fix_crypto_perms "${PERSIST}"
  rsync_to "${PERSIST}" "${LIVE}"
  fix_crypto_perms "${LIVE}"
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
