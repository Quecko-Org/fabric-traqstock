#!/usr/bin/env bash
#
# Install or update BISL on Ubuntu/Debian VPS.
# Safe for re-runs: will NOT tear down a healthy Fabric network.
# Run inside extracted bisl-deploy/:
#   sudo ./scripts/install-vps.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-paths.sh
source "${SCRIPT_DIR}/lib-paths.sh"
bisl_resolve_paths "${SCRIPT_DIR}"

DEPLOY_ROOT="${BISL_DEPLOY_ROOT}"
RPC_DIR="${BISL_RPC_DIR}"
FABRIC_DIR="${BISL_FABRIC_DIR}"

echo "==> BISL VPS install"
echo "    Deploy root: ${DEPLOY_ROOT}"
echo "    Fabric dir:  ${FABRIC_DIR}"

# --- Prerequisites ---
if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg rsync
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
fi

if ! command -v rsync >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq rsync
fi

if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]]; then
  echo "==> Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

# --- Restore crypto BEFORE touching network (CI may have wiped workspace) ---
echo "==> Ensuring Fabric crypto is present"
mkdir -p /var/lib/bisl
export BISL_CRYPTO_PERSIST="${BISL_CRYPTO_PERSIST:-/var/lib/bisl/organizations}"
"${SCRIPT_DIR}/persist-crypto.sh" restore || true

# --- RPC dependencies ---
echo "==> Installing RPC dependencies"
cd "${RPC_DIR}"
npm install --omit=dev

# --- Environment ---
if [[ ! -f "${RPC_DIR}/.env" ]]; then
  if [[ -f "${RPC_DIR}/.env.example" ]]; then
    cp "${RPC_DIR}/.env.example" "${RPC_DIR}/.env"
  elif [[ -f "${RPC_DIR}/.env.vps" ]]; then
    cp "${RPC_DIR}/.env.vps" "${RPC_DIR}/.env"
  else
    echo "No .env.example or .env.vps found" >&2
    exit 1
  fi
  WRITE_KEY="$(openssl rand -hex 32)"
  READ_KEY="$(openssl rand -hex 32)"
  if grep -q 'change-me-write-key' "${RPC_DIR}/.env" 2>/dev/null; then
    sed -i "s/change-me-write-key/${WRITE_KEY}/" "${RPC_DIR}/.env"
    sed -i "s/change-me-read-key/${READ_KEY}/" "${RPC_DIR}/.env"
  else
    {
      echo "WRITE_API_KEY=${WRITE_KEY}"
      echo "READ_API_KEY=${READ_KEY}"
      echo "REQUIRE_AUTH=true"
    } >> "${RPC_DIR}/.env"
  fi
  echo ""
  echo "==> Generated API keys (saved to rpc/.env):"
  echo "    WRITE_API_KEY=${WRITE_KEY}"
  echo "    READ_API_KEY=${READ_KEY}"
  echo ""
fi

# Load VPS defaults without clobbering existing secrets
if [[ -f "${RPC_DIR}/.env.vps" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${RPC_DIR}/.env.vps"
  set +a
fi

export FABRIC_ROOT="${FABRIC_DIR}"

echo "==> Starting Fabric network (skip if already up)"
"${SCRIPT_DIR}/start-network.sh"

echo "==> Persisting crypto outside deploy workspace"
"${SCRIPT_DIR}/persist-crypto.sh" save

echo "==> Setting up wallet"
cd "${RPC_DIR}"
FABRIC_ROOT="${FABRIC_DIR}" npm run setup:wallet

echo "==> Deploying chaincode"
"${SCRIPT_DIR}/deploy-chaincode.sh"

echo "==> Starting RPC for RBAC init"
# shellcheck disable=SC1091
source "${RPC_DIR}/.env"
FABRIC_ROOT="${FABRIC_DIR}" "${SCRIPT_DIR}/start-rpc.sh" &
RPC_PID=$!
sleep 4

echo "==> Initializing RBAC"
curl -sf -X POST "http://localhost:${PORT:-4000}/v1/admin/init-rbac" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${WRITE_API_KEY}" \
  -d '{"adminMSP":"Org1MSP","agentMSP":"Org2MSP"}' && echo "RBAC initialized" || echo "RBAC init failed — run manually after RPC is up"

kill "${RPC_PID}" 2>/dev/null || true
wait "${RPC_PID}" 2>/dev/null || true

# Point Explorer at live crypto (also durable after persist)
if [[ -d "${BISL_EXPLORER_DIR}" ]]; then
  cat > "${BISL_EXPLORER_DIR}/.env" <<EOF
PORT=8080
EXPLORER_CONFIG_FILE_PATH=./config.json
EXPLORER_PROFILE_DIR_PATH=./connection-profile
FABRIC_CRYPTO_PATH=${BISL_CRYPTO_LIVE}
EXPLORER_DB_PASSWORD=${EXPLORER_DB_PASSWORD:-BislExpDb2026!Pg_7mXq}
EOF
fi

echo ""
echo "==> Install complete"
echo ""
echo "Crypto durable copy: ${BISL_CRYPTO_PERSIST:-/var/lib/bisl/organizations}"
echo "  (survives Actions workspace cleans — do NOT delete)"
echo ""
echo "Start RPC:"
echo "  ${SCRIPT_DIR}/start-rpc.sh"
echo ""
echo "Start Explorer (admin, localhost:8080 / SSH tunnel):"
echo "  ${SCRIPT_DIR}/start-explorer.sh"
echo ""
echo "Or install systemd service:"
echo "  cp ${SCRIPT_DIR}/bisl-rpc.service /etc/systemd/system/"
echo "  sed -i 's|/opt/bisl-deploy|${DEPLOY_ROOT}|g' /etc/systemd/system/bisl-rpc.service"
echo "  systemctl daemon-reload && systemctl enable --now bisl-rpc"
