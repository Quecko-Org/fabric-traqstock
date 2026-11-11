#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

FABRIC_DIR="${BISL_FABRIC_DIR}"
CHAINCODE_DIR="${BISL_CHAINCODE_DIR}"
TN="${BISL_TEST_NETWORK}"

cd "${TN}"
export PATH="${FABRIC_DIR}/bin:${PATH}"
export FABRIC_CFG_PATH="${FABRIC_DIR}/config"

./network.sh deployCC \
  -ccn bislcc \
  -ccp "${CHAINCODE_DIR}" \
  -ccl javascript

echo "Chaincode bislcc deployed"
