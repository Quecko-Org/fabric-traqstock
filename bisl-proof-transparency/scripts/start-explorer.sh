#!/usr/bin/env bash
#
# Start Hyperledger Explorer (admin-only, localhost:8080).
# Works from fabric-samples OR bisl-deploy package.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -d "${SCRIPT_DIR}/../explorer" && -f "${SCRIPT_DIR}/../explorer/docker-compose.yaml" ]]; then
  # bisl-proof-transparency/scripts → explorer
  # or bisl-deploy/scripts → explorer
  EXPLORER_DIR="$(cd "${SCRIPT_DIR}/../explorer" && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../bisl-proof-transparency/explorer" ]]; then
  EXPLORER_DIR="$(cd "${SCRIPT_DIR}/../../bisl-proof-transparency/explorer" && pwd)"
else
  echo "Explorer folder not found"
  exit 1
fi

cd "${EXPLORER_DIR}"

# Resolve crypto path
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${FABRIC_CRYPTO_PATH:-}" ]]; then
  if [[ -d "${EXPLORER_DIR}/../fabric/test-network/organizations" ]]; then
    FABRIC_CRYPTO_PATH="${EXPLORER_DIR}/../fabric/test-network/organizations"
  elif [[ -d "${EXPLORER_DIR}/../../test-network/organizations" ]]; then
    FABRIC_CRYPTO_PATH="${EXPLORER_DIR}/../../test-network/organizations"
  else
    echo "FABRIC_CRYPTO_PATH not set and organizations/ not found"
    echo "Start Fabric first, then set FABRIC_CRYPTO_PATH in explorer/.env"
    exit 1
  fi
fi

FABRIC_CRYPTO_PATH="$(cd "${FABRIC_CRYPTO_PATH}" && pwd)"
export FABRIC_CRYPTO_PATH

KEYSTORE_DIR="${FABRIC_CRYPTO_PATH}/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
if [[ ! -d "${KEYSTORE_DIR}" ]]; then
  echo "Admin keystore not found: ${KEYSTORE_DIR}"
  echo "Run network up with -ca first so organizations/ exists"
  exit 1
fi

# Fabric CA creates a random key filename; Explorer expects a stable path (priv_sk)
PRIV_KEY="$(find "${KEYSTORE_DIR}" -type f | head -n 1 || true)"
if [[ -z "${PRIV_KEY}" ]]; then
  echo "No private key in ${KEYSTORE_DIR}"
  exit 1
fi
ln -sfn "$(basename "${PRIV_KEY}")" "${KEYSTORE_DIR}/priv_sk"
echo "Linked Admin key → ${KEYSTORE_DIR}/priv_sk"

if ! docker network inspect fabric_test >/dev/null 2>&1; then
  echo "Docker network fabric_test not found. Start Fabric first:"
  echo "  ./scripts/start-network.sh"
  exit 1
fi

PROFILE="${EXPLORER_DIR}/connection-profile/bisl-network.json"
if grep -q 'CHANGE_ME_strong_explorer_password' "${PROFILE}"; then
  echo ""
  echo "WARNING: Explorer still uses the placeholder password."
  echo "  Edit: ${PROFILE}"
  echo "  Change client.adminCredential.password before production use."
  echo ""
fi

echo "Starting Explorer (bound to 127.0.0.1:8080)..."
docker compose up -d

echo ""
echo "Explorer is up."
echo "  Local:   http://localhost:8080"
echo "  Login:   see connection-profile/bisl-network.json (adminCredential)"
echo ""
echo "AWS SSH tunnel (from your laptop):"
echo "  ssh -i your-key.pem -L 8080:127.0.0.1:8080 ubuntu@YOUR_EC2_IP"
echo "  then open http://localhost:8080"
