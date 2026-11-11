#!/usr/bin/env bash
#
# Ensure Fabric peer/configtxgen/etc binaries work on THIS machine.
# Repo may contain macOS arm64 binaries; EC2 needs linux-amd64.
# Caches downloads under /var/lib/bisl/fabric so CI does not re-download every run.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

FABRIC_DIR="${BISL_FABRIC_DIR}"
FABRIC_VERSION="${FABRIC_VERSION:-2.5.12}"
CA_VERSION="${CA_VERSION:-1.5.15}"
CACHE_ROOT="${BISL_FABRIC_CACHE:-/var/lib/bisl/fabric}"

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch_raw="$(uname -m)"
case "${arch_raw}" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "Unsupported arch: ${arch_raw}" >&2
    exit 1
    ;;
esac

peer_ok() {
  local peer_bin="$1"
  [[ -x "${peer_bin}" ]] || return 1
  # Must actually execute on this OS/arch
  "${peer_bin}" version >/dev/null 2>&1
}

config_ok() {
  [[ -f "${FABRIC_DIR}/config/core.yaml" ]]
}

install_from_cache_or_download() {
  local cache_bin="${CACHE_ROOT}/bin"
  local cache_cfg="${CACHE_ROOT}/config"

  run_as_root mkdir -p "${CACHE_ROOT}"
  run_as_root chown -R "$(id -u):$(id -g)" "${CACHE_ROOT}" 2>/dev/null || true

  if ! peer_ok "${cache_bin}/peer" || [[ ! -f "${cache_cfg}/core.yaml" ]]; then
    echo "==> Downloading Fabric ${FABRIC_VERSION} + CA ${CA_VERSION} for ${os_name}-${arch}"
    local tmp
    tmp="$(mktemp -d)"
    cleanup() { rm -rf "${tmp}"; }
    trap cleanup EXIT

    curl -fsSL \
      "https://github.com/hyperledger/fabric/releases/download/v${FABRIC_VERSION}/hyperledger-fabric-${os_name}-${arch}-${FABRIC_VERSION}.tar.gz" \
      | tar -xz -C "${tmp}"

    curl -fsSL \
      "https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/hyperledger-fabric-ca-${os_name}-${arch}-${CA_VERSION}.tar.gz" \
      | tar -xz -C "${tmp}"

    mkdir -p "${cache_bin}" "${cache_cfg}"
    rsync -a "${tmp}/bin/" "${cache_bin}/"
    rsync -a "${tmp}/config/" "${cache_cfg}/"
    chmod +x "${cache_bin}/"*
    trap - EXIT
    rm -rf "${tmp}"
    echo "Cached Fabric binaries at ${CACHE_ROOT}"
  else
    echo "Using cached Fabric binaries at ${CACHE_ROOT}"
  fi

  echo "==> Installing binaries into ${FABRIC_DIR}"
  mkdir -p "${FABRIC_DIR}/bin" "${FABRIC_DIR}/config"
  # Replace broken macOS symlink/bin trees with real linux binaries
  if [[ -L "${FABRIC_DIR}/bin" ]]; then
    rm -f "${FABRIC_DIR}/bin"
    mkdir -p "${FABRIC_DIR}/bin"
  fi
  if [[ -L "${FABRIC_DIR}/config" ]]; then
    rm -f "${FABRIC_DIR}/config"
    mkdir -p "${FABRIC_DIR}/config"
  fi
  rsync -a "${cache_bin}/" "${FABRIC_DIR}/bin/"
  rsync -a "${cache_cfg}/" "${FABRIC_DIR}/config/"
  chmod +x "${FABRIC_DIR}/bin/"*

  # network.sh also looks for binaries on PATH via ../bin historically;
  # keep a copy under test-network/bin for scripts that expect it there.
  mkdir -p "${BISL_TEST_NETWORK}/bin"
  rsync -a "${cache_bin}/" "${BISL_TEST_NETWORK}/bin/"
  chmod +x "${BISL_TEST_NETWORK}/bin/"*
}

echo "==> Checking Fabric binaries (${os_name}/${arch})"
if peer_ok "${FABRIC_DIR}/bin/peer" && config_ok; then
  echo "Fabric binaries OK: $("${FABRIC_DIR}/bin/peer" version | head -n 1)"
  exit 0
fi

echo "Fabric binaries missing or wrong architecture — repairing"
install_from_cache_or_download

if ! peer_ok "${FABRIC_DIR}/bin/peer" || ! config_ok; then
  echo "Failed to install working Fabric binaries" >&2
  exit 1
fi

echo "Fabric binaries ready: $("${FABRIC_DIR}/bin/peer" version | head -n 1)"
