# BISL Hyperledger Explorer (Admin Only)

Private Fabric block/transaction viewer for **admins only**.

- UI binds to **`127.0.0.1:8080`** (not public)
- Login required (`enableAuthentication: true`)
- On AWS: access via **SSH tunnel** (recommended)

## Prerequisites

1. Fabric test-network is running (`fabric_test` Docker network exists)
2. Channel `mychannel` exists
3. Crypto material exists under `test-network/organizations`

```bash
docker network ls | grep fabric_test
```

## 1. Sample admin credentials (change later)

Default login (already set in `connection-profile/bisl-network.json`):

| Field | Sample value |
|-------|----------------|
| User | `bisladmin` |
| Password | `BislExp2026!Admin_9kRx` |

Sample DB password in `.env.example` (no `#` — `#` starts comments in `.env`):

```bash
EXPLORER_DB_PASSWORD=BislExpDb2026!Pg_7mXq
```

Change both before long-term production use.

## 2. Start Explorer

### Local (fabric-samples)

```bash
cd bisl-proof-transparency/explorer
cp -n .env.example .env   # first time only
# .env points FABRIC_CRYPTO_PATH at ../../test-network/organizations
docker compose up -d
```

### VPS / AWS (`bisl-deploy`)

```bash
cd /opt/bisl-deploy/explorer
# Ensure .env has:
# FABRIC_CRYPTO_PATH=../fabric/test-network/organizations
docker compose up -d
```

Or use the helper:

```bash
./scripts/start-explorer.sh
```

## 3. Open UI (admin)

### Local

Open [http://localhost:8080](http://localhost:8080)

Login (sample — change later):
- User: `bisladmin`
- Password: `BislExp2026!Admin_9kRx`

### AWS / remote EC2 (SSH tunnel — recommended)

**Do not open port 8080 in the AWS Security Group.**

On your laptop:

```bash
ssh -i your-key.pem -L 8080:127.0.0.1:8080 ubuntu@YOUR_EC2_IP
```

Keep that SSH session open, then on your laptop open:

[http://localhost:8080](http://localhost:8080)

Login with the Explorer admin credentials.

## 4. Stop Explorer

```bash
cd bisl-proof-transparency/explorer   # or /opt/bisl-deploy/explorer
docker compose down -v
```

`-v` removes Explorer DB/wallet volumes (needed after network crypto reset).

## Security checklist

- [ ] Changed default Explorer login password
- [ ] Changed `EXPLORER_DB_PASSWORD`
- [ ] Port `8080` **not** open in Security Group (`0.0.0.0/0`)
- [ ] Access only via SSH tunnel (or IP allowlist if required)
- [ ] Fabric peer ports remain closed to the internet

## What admin can see

- Channel `mychannel`
- Blocks and transactions
- Chaincode invokes (`AnchorDatasetProof`, `InitRBAC`, etc.)
- Tx IDs / timestamps / peer endorsements

Public apps should keep using the RPC API (`:4000`) with API keys — not Explorer.
