#!/usr/bin/env bash
#
# Ensure Fabric binaries work on THIS host (linux-amd64 on EC2).
# Cache: /var/lib/bisl/fabric
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

SUDO=()
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  fi
fi

os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$(uname -m)" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

peer_ok() {
  local b="$1"
  [[ -e "${b}" ]] || return 1
  # Wrong-arch binaries return 126/127; treat as not ok
  "${b}" version >/dev/null 2>&1
}

config_ok() {
  [[ -f "${FABRIC_DIR}/config/core.yaml" ]]
}

# Force path to be a real directory owned by current user.
force_dir() {
  local d="$1"
  "${SUDO[@]}" mkdir -p "$(dirname "${d}")"
  if [[ -L "${d}" ]]; then
    echo "Removing symlink ${d} -> $(readlink "${d}" || true)"
    "${SUDO[@]}" rm -f "${d}"
  elif [[ -e "${d}" && ! -d "${d}" ]]; then
    echo "Removing non-dir ${d}"
    "${SUDO[@]}" rm -f "${d}"
  fi
  "${SUDO[@]}" mkdir -p "${d}"
  "${SUDO[@]}" chown -R "$(id -u):$(id -g)" "${d}" 2>/dev/null || true
}

copy_tree() {
  local src="$1"
  local dst="$2"
  force_dir "${dst}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${src}/" "${dst}/"
  else
    "${SUDO[@]}" cp -a "${src}/." "${dst}/"
    "${SUDO[@]}" chown -R "$(id -u):$(id -g)" "${dst}" 2>/dev/null || true
  fi
}

echo "==> Checking Fabric binaries (${os_name}/${arch}) in ${FABRIC_DIR}"

if peer_ok "${FABRIC_DIR}/bin/peer" && config_ok; then
  echo "Fabric binaries OK: $("${FABRIC_DIR}/bin/peer" version | head -n 1)"
  exit 0
fi

echo "Fabric binaries missing or wrong architecture — repairing"

force_dir "${CACHE_ROOT}"
force_dir "${CACHE_ROOT}/bin"
force_dir "${CACHE_ROOT}/config"

if ! peer_ok "${CACHE_ROOT}/bin/peer" || [[ ! -f "${CACHE_ROOT}/config/core.yaml" ]]; then
  echo "==> Downloading Fabric ${FABRIC_VERSION} + CA ${CA_VERSION} for ${os_name}-${arch}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  curl -fsSL \
    "https://github.com/hyperledger/fabric/releases/download/v${FABRIC_VERSION}/hyperledger-fabric-${os_name}-${arch}-${FABRIC_VERSION}.tar.gz" \
    | tar -xz -C "${tmp}"

  curl -fsSL \
    "https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/hyperledger-fabric-ca-${os_name}-${arch}-${CA_VERSION}.tar.gz" \
    | tar -xz -C "${tmp}"

  [[ -d "${tmp}/bin" && -d "${tmp}/config" ]] || {
    echo "Bad archive layout:" >&2
    ls -la "${tmp}" >&2
    exit 1
  }

  copy_tree "${tmp}/bin" "${CACHE_ROOT}/bin"
  copy_tree "${tmp}/config" "${CACHE_ROOT}/config"
  chmod +x "${CACHE_ROOT}/bin/"* || true
  trap - EXIT
  rm -rf "${tmp}"
  echo "Cached at ${CACHE_ROOT}"
else
  echo "Using cache ${CACHE_ROOT}"
fi

echo "==> Installing into ${FABRIC_DIR}"
force_dir "${FABRIC_DIR}"
force_dir "${FABRIC_DIR}/bin"
force_dir "${FABRIC_DIR}/config"
force_dir "${BISL_TEST_NETWORK}/bin"

copy_tree "${CACHE_ROOT}/bin" "${FABRIC_DIR}/bin"
copy_tree "${CACHE_ROOT}/config" "${FABRIC_DIR}/config"
copy_tree "${CACHE_ROOT}/bin" "${BISL_TEST_NETWORK}/bin"
chmod +x "${FABRIC_DIR}/bin/"* "${BISL_TEST_NETWORK}/bin/"* || true

# Sanity: show what we installed
ls -la "${FABRIC_DIR}/bin" | head
file "${FABRIC_DIR}/bin/peer" || true

if ! peer_ok "${FABRIC_DIR}/bin/peer" || ! config_ok; then
  echo "ERROR: peer still not runnable after install" >&2
  "${FABRIC_DIR}/bin/peer" version 2>&1 || true
  exit 1
fi

echo "Fabric binaries ready: $("${FABRIC_DIR}/bin/peer" version | head -n 1)"
