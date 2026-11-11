#!/usr/bin/env bash
# Shared path resolution for local fabric-samples and VPS bisl-deploy layouts.
# Usage from sibling scripts:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   # shellcheck source=lib-paths.sh
#   source "${SCRIPT_DIR}/lib-paths.sh"
#   bisl_resolve_paths "${SCRIPT_DIR}"

bisl_resolve_paths() {
  local script_dir="${1:?script dir required}"
  local deploy_root
  deploy_root="$(cd "${script_dir}/.." && pwd)"

  BISL_SCRIPT_DIR="${script_dir}"
  BISL_DEPLOY_ROOT="${deploy_root}"

  # VPS package: bisl-deploy/{fabric,rpc,chaincode,explorer,scripts}
  if [[ -d "${deploy_root}/fabric/test-network" ]]; then
    BISL_FABRIC_DIR="${deploy_root}/fabric"
    BISL_RPC_DIR="${deploy_root}/rpc"
    BISL_CHAINCODE_DIR="${deploy_root}/chaincode"
    BISL_EXPLORER_DIR="${deploy_root}/explorer"
  # Local fabric-samples: bisl-proof-transparency next to test-network/
  elif [[ -d "${deploy_root}/../test-network" ]]; then
    BISL_FABRIC_DIR="$(cd "${deploy_root}/.." && pwd)"
    BISL_RPC_DIR="${deploy_root}/rest-api-javascript"
    BISL_CHAINCODE_DIR="${deploy_root}/chaincode-javascript"
    BISL_EXPLORER_DIR="${deploy_root}/explorer"
  else
    echo "Cannot resolve Fabric layout from ${deploy_root}" >&2
    return 1
  fi

  BISL_TEST_NETWORK="${BISL_FABRIC_DIR}/test-network"
  BISL_CRYPTO_LIVE="${BISL_TEST_NETWORK}/organizations"
  # Optional override; persist-crypto.sh chooses /var/lib/bisl or ~/.bisl
  : "${BISL_CRYPTO_PERSIST:=}"
}
