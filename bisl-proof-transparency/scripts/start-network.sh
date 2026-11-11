#!/usr/bin/env bash
#
# Ensure Fabric test-network is up WITH crypto on disk.
# Never treats "peer container Up" as healthy if organizations/ is missing.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

TN="${BISL_TEST_NETWORK}"
FABRIC_DIR="${BISL_FABRIC_DIR}"
LIVE="${BISL_CRYPTO_LIVE}"

admin_ok() {
  [[ -d "${1}/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore" ]] \
    && [[ -d "${1}/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls" ]]
}

peer_up() {
  docker ps --format '{{.Names}}' | grep -q '^peer0.org1.example.com$'
}

cd "${TN}"
export PATH="${FABRIC_DIR}/bin:${PATH}"
export FABRIC_CFG_PATH="${FABRIC_DIR}/config"
export BISL_CRYPTO_PERSIST="${BISL_CRYPTO_PERSIST:-/var/lib/bisl/organizations}"

# 1) Healthy: peers up + crypto present
if peer_up && admin_ok "${LIVE}"; then
  echo "Fabric network already running with crypto on disk"
  "${SCRIPT_DIR}/persist-crypto.sh" save || true
  exit 0
fi

# 2) Peers up but crypto wiped (broken bind mounts) → restore if possible
if peer_up && ! admin_ok "${LIVE}"; then
  echo "WARNING: peers are up but organizations/ missing — restoring durable crypto"
  if "${SCRIPT_DIR}/persist-crypto.sh" restore; then
    echo "Crypto restored under running peers"
    exit 0
  fi
  echo "WARNING: no durable crypto — recreating Fabric network (ledger volumes reset)"
  ./network.sh down 2>/dev/null || true
  ./network.sh up createChannel -ca
  "${SCRIPT_DIR}/persist-crypto.sh" save
  echo "Fabric network recreated"
  exit 0
fi

# 3) Peers down — try restore then start existing containers
if ! admin_ok "${LIVE}"; then
  "${SCRIPT_DIR}/persist-crypto.sh" restore || true
fi

if docker ps -a --format '{{.Names}}' | grep -q '^peer0.org1.example.com$' && admin_ok "${LIVE}"; then
  echo "Starting existing Fabric containers..."
  docker start ca_org1 ca_org2 ca_orderer orderer.example.com peer0.org1.example.com peer0.org2.example.com 2>/dev/null || true
  sleep 3
  if peer_up && admin_ok "${LIVE}"; then
    echo "Fabric network restarted"
    "${SCRIPT_DIR}/persist-crypto.sh" save || true
    exit 0
  fi
fi

# 4) Fresh network
echo "Bringing Fabric network up (new)..."
./network.sh down 2>/dev/null || true
./network.sh up createChannel -ca
"${SCRIPT_DIR}/persist-crypto.sh" save
echo "Fabric network is up"
