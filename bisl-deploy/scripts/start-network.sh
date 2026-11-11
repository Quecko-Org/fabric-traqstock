#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

TN="${BISL_TEST_NETWORK}"
FABRIC_DIR="${BISL_FABRIC_DIR}"

cd "${TN}"
export PATH="${FABRIC_DIR}/bin:${PATH}"
export FABRIC_CFG_PATH="${FABRIC_DIR}/config"

if docker ps --format '{{.Names}}' | grep -q '^peer0.org1.example.com$'; then
  echo "Fabric network already running"
  # Ensure durable copy exists (no-op if already persisted)
  if [[ -d "${BISL_CRYPTO_LIVE}" ]]; then
    "${SCRIPT_DIR}/persist-crypto.sh" save || true
  fi
  exit 0
fi

# Prefer restore over wiping a healthy ledger volume set
if [[ ! -d "${BISL_CRYPTO_LIVE}/peerOrganizations" ]]; then
  "${SCRIPT_DIR}/persist-crypto.sh" restore || true
fi

if docker ps -a --format '{{.Names}}' | grep -q '^peer0.org1.example.com$'; then
  echo "Starting existing Fabric containers (crypto restore path)..."
  # Bring compose stack back if containers exist but are stopped
  if [[ -f compose/compose-test-net.yaml ]]; then
    docker start ca_org1 ca_org2 ca_orderer orderer.example.com peer0.org1.example.com peer0.org2.example.com 2>/dev/null || true
  fi
  if docker ps --format '{{.Names}}' | grep -q '^peer0.org1.example.com$'; then
    echo "Fabric network restarted from existing containers"
    "${SCRIPT_DIR}/persist-crypto.sh" save || true
    exit 0
  fi
fi

echo "Bringing Fabric network up (new)..."
./network.sh down 2>/dev/null || true
./network.sh up createChannel -ca

"${SCRIPT_DIR}/persist-crypto.sh" save || true

echo "Fabric network is up"
