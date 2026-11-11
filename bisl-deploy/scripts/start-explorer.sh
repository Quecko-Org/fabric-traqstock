#!/usr/bin/env bash
#
# Start Hyperledger Explorer (admin-only, localhost:8080).
# Works from fabric-samples OR bisl-deploy package.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

EXPLORER_DIR="${BISL_EXPLORER_DIR}"
cd "${EXPLORER_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Prefer durable crypto if live path was wiped by CI
if [[ -z "${FABRIC_CRYPTO_PATH:-}" ]] || [[ ! -d "${FABRIC_CRYPTO_PATH}/peerOrganizations" ]]; then
  if [[ -d "${BISL_CRYPTO_LIVE}/peerOrganizations" ]]; then
    FABRIC_CRYPTO_PATH="${BISL_CRYPTO_LIVE}"
  elif [[ -d "${HOME}/.bisl/organizations/peerOrganizations" ]]; then
    FABRIC_CRYPTO_PATH="${HOME}/.bisl/organizations"
  elif [[ -d /var/lib/bisl/organizations/peerOrganizations ]]; then
    FABRIC_CRYPTO_PATH=/var/lib/bisl/organizations
  else
    echo "FABRIC_CRYPTO_PATH not set and organizations/ not found"
    echo "Try: ./scripts/persist-crypto.sh restore"
    echo "Or start Fabric first, then set FABRIC_CRYPTO_PATH in explorer/.env"
    exit 1
  fi
fi

# If live path empty but durable exists, restore now
if [[ ! -d "${BISL_CRYPTO_LIVE}/peerOrganizations" ]]; then
  "${SCRIPT_DIR}/persist-crypto.sh" restore || true
  if [[ -d "${BISL_CRYPTO_LIVE}/peerOrganizations" ]]; then
    FABRIC_CRYPTO_PATH="${BISL_CRYPTO_LIVE}"
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
PRIV_KEY="$(find "${KEYSTORE_DIR}" -type f ! -name 'priv_sk' | head -n 1 || true)"
if [[ -z "${PRIV_KEY}" ]]; then
  PRIV_KEY="$(find "${KEYSTORE_DIR}" -type f | head -n 1 || true)"
fi
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

# Ensure .env has absolute crypto path for compose
if [[ -f .env ]]; then
  if grep -q '^FABRIC_CRYPTO_PATH=' .env; then
    sed -i.bak "s|^FABRIC_CRYPTO_PATH=.*|FABRIC_CRYPTO_PATH=${FABRIC_CRYPTO_PATH}|" .env
    rm -f .env.bak
  else
    echo "FABRIC_CRYPTO_PATH=${FABRIC_CRYPTO_PATH}" >> .env
  fi
else
  cat > .env <<EOF
PORT=8080
EXPLORER_CONFIG_FILE_PATH=./config.json
EXPLORER_PROFILE_DIR_PATH=./connection-profile
FABRIC_CRYPTO_PATH=${FABRIC_CRYPTO_PATH}
EXPLORER_DB_PASSWORD=BislExpDb2026!Pg_7mXq
EOF
fi

PROFILE="${EXPLORER_DIR}/connection-profile/bisl-network.json"
if grep -q 'BislExp2026!Admin_9kRx' "${PROFILE}"; then
  echo ""
  echo "NOTE: Explorer is using the sample admin password."
  echo "  Login: bisladmin / BislExp2026!Admin_9kRx"
  echo "  Change it later in: ${PROFILE}"
  echo ""
fi

export EXPLORER_BIND="${EXPLORER_BIND:-0.0.0.0}"
echo "Starting Explorer (bound to ${EXPLORER_BIND}:8080)..."
echo "  FABRIC_CRYPTO_PATH=${FABRIC_CRYPTO_PATH}"
docker compose up -d

echo ""
echo "Explorer is up."
echo "  Local:    http://localhost:8080"
echo "  Public:   http://YOUR_EC2_IP:8080  (Security Group must allow TCP 8080)"
echo "  Login:    see connection-profile/bisl-network.json (adminCredential)"
echo "  Localhost-only mode: EXPLORER_BIND=127.0.0.1 ./scripts/start-explorer.sh"
