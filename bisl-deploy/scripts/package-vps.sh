#!/usr/bin/env bash
#
# Package a minimal BISL deployment bundle for VPS/cloud.
# Run from fabric-samples root:
#   ./bisl-proof-transparency/scripts/package-vps.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ROOT}/bisl-deploy"
ARCHIVE="${ROOT}/bisl-deploy.tar.gz"

echo "==> Packaging BISL deploy bundle"
echo "    Source: ${ROOT}"
echo "    Output: ${OUT}"

rm -rf "${OUT}"
mkdir -p "${OUT}"/{fabric,rpc,chaincode,scripts,explorer}

# Fabric network essentials
echo "==> Copying Fabric binaries and config"
cp -R "${ROOT}/bin" "${OUT}/fabric/"
cp -R "${ROOT}/config" "${OUT}/fabric/"

echo "==> Copying test-network"
rsync -a \
  --exclude 'system-genesis-block' \
  --exclude 'channel-artifacts' \
  --exclude 'organizations/peerOrganizations' \
  --exclude 'organizations/ordererOrganizations' \
  --exclude 'compose/podman' \
  "${ROOT}/test-network/" "${OUT}/fabric/test-network/"

# Keep only CA/register/ccp bootstrap assets (never ship generated MSPs or CA runtime DB/certs)
echo "==> Seeding organizations bootstrap scripts"
rm -rf "${OUT}/fabric/test-network/organizations"
mkdir -p "${OUT}/fabric/test-network/organizations"
while IFS= read -r f; do
  rel="${f#test-network/}"
  mkdir -p "${OUT}/fabric/test-network/$(dirname "${rel}")"
  cp "${ROOT}/${f}" "${OUT}/fabric/test-network/${rel}"
done < <(git -C "${ROOT}" ls-files 'test-network/organizations/**')
chmod +x "${OUT}/fabric/test-network/organizations/fabric-ca/registerEnroll.sh" \
  "${OUT}/fabric/test-network/organizations/ccp-generate.sh" \
  "${OUT}/fabric/test-network/organizations/cfssl/registerEnroll.sh" 2>/dev/null || true

# Chaincode (JS only)
echo "==> Copying chaincode"
rsync -a \
  --exclude 'node_modules' \
  "${ROOT}/bisl-proof-transparency/chaincode-javascript/" "${OUT}/chaincode/"

# RPC API
echo "==> Copying RPC API"
rsync -a \
  --exclude 'node_modules' \
  --exclude 'wallet' \
  "${ROOT}/bisl-proof-transparency/rest-api-javascript/" "${OUT}/rpc/"
mkdir -p "${OUT}/rpc/wallet"

# Hyperledger Explorer (admin-only)
echo "==> Copying Explorer"
rsync -a \
  --exclude 'walletstore' \
  "${ROOT}/bisl-proof-transparency/explorer/" "${OUT}/explorer/"
# VPS crypto path relative to explorer/
cat > "${OUT}/explorer/.env" <<'EOF'
PORT=8080
EXPLORER_CONFIG_FILE_PATH=./config.json
EXPLORER_PROFILE_DIR_PATH=./connection-profile
FABRIC_CRYPTO_PATH=../fabric/test-network/organizations
EXPLORER_DB_PASSWORD=BislExpDb2026!Pg_7mXq
EOF

# Deploy scripts and docs
echo "==> Copying deploy scripts"
cp "${ROOT}/bisl-proof-transparency/scripts/lib-paths.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/persist-crypto.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/sync-to-opt.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/ensure-fabric-binaries.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/install-vps.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/start-network.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/deploy-chaincode.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/start-rpc.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/start-explorer.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/scripts/stop-explorer.sh" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/deploy/README-DEPLOY.md" "${OUT}/README-DEPLOY.md"
cp "${ROOT}/bisl-proof-transparency/deploy/README-AWS.md" "${OUT}/README-AWS.md"
cp "${ROOT}/bisl-proof-transparency/deploy/bisl-rpc.service" "${OUT}/scripts/"
cp "${ROOT}/bisl-proof-transparency/deploy/.env.production.example" "${OUT}/rpc/.env.example"

chmod +x "${OUT}/scripts/"*.sh

# VPS-specific env defaults
cat > "${OUT}/rpc/.env.vps" <<'EOF'
PORT=4000
FABRIC_ROOT=../fabric
DISCOVERY_AS_LOCALHOST=true
REQUIRE_AUTH=true
FABRIC_ORG=org1
FABRIC_IDENTITY=appUserOrg1
CHANNEL_NAME=mychannel
CHAINCODE_NAME=bislcc
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX=120
EOF

echo "==> Creating archive: ${ARCHIVE}"
tar -czf "${ARCHIVE}" -C "${ROOT}" bisl-deploy

echo ""
echo "Done."
echo "  Folder:  ${OUT}"
echo "  Archive: ${ARCHIVE}"
echo ""
echo "Upload to VPS:"
echo "  scp ${ARCHIVE} user@your-vps:/opt/"
echo "  ssh user@your-vps 'cd /opt && tar -xzf bisl-deploy.tar.gz && cd bisl-deploy && sudo ./scripts/install-vps.sh'"
