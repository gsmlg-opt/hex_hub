# HexHub

[![CI](https://github.com/gsmlg-opt/hex_hub/actions/workflows/ci.yml/badge.svg)](https://github.com/gsmlg-opt/hex_hub/actions/workflows/ci.yml)
[![Test](https://github.com/gsmlg-opt/hex_hub/actions/workflows/test.yml/badge.svg)](https://github.com/gsmlg-opt/hex_hub/actions/workflows/test.yml)
[![E2E Tests](https://github.com/gsmlg-opt/hex_hub/actions/workflows/e2e.yml/badge.svg)](https://github.com/gsmlg-opt/hex_hub/actions/workflows/e2e.yml)
[![Docker Image](https://ghcr-badge.egpl.dev/gsmlg-dev/hex-hub/latest_tag?trim=major&label=docker&color=blue)](https://github.com/orgs/gsmlg-dev/packages/container/package/hex-hub)

HexHub is a private Hex package manager and HexDocs server built with Phoenix. It is intended to run as a drop-in Hex registry for private Elixir packages, with optional upstream proxying and caching for public packages from hex.pm.

The application uses Mnesia for metadata, local filesystem or S3-compatible object storage for package artifacts, and two Phoenix endpoints:

- Main package/API endpoint: `http://localhost:4360`
- Admin dashboard endpoint: `http://localhost:4361`

## Features

- Hex client compatible package registry endpoints
- Package publishing, release download, retirement, ownership, and API key management
- Hosted package documentation upload and serving
- Public HTML package browser
- Admin dashboard for packages, users, repositories, storage, backups, upstream config, and publish settings
- Optional anonymous publishing mode
- Upstream proxy and cache for hex.pm-compatible repositories
- Local filesystem or S3-compatible storage
- Mnesia persistence without PostgreSQL or another external database
- Optional Mnesia/libcluster clustering
- Optional MCP JSON-RPC and WebSocket server for AI client integration
- Backup export/import support

## Requirements

- Elixir 1.17 or newer
- Erlang/OTP 26 or newer
- Node package dependencies installed through the `npm` Mix package
- `mise` and Zig 0.15.2 only when QuickBEAM must be compiled from source, such as Intel macOS

## Quick Start

```bash
git clone https://github.com/gsmlg-opt/hex_hub.git
cd hex_hub

mix setup
mix phx.server
```

Open:

- Package browser/API: http://localhost:4360
- Admin dashboard: http://localhost:4361

The default development storage paths are:

- Mnesia data: `priv/mnesia/dev`
- Package and docs storage: `priv/storage`

## Development Commands

```bash
mix setup                         # Fetch deps, compile QuickBEAM when needed, build assets
mix phx.server                    # Start both web endpoints
mix assets.build                  # Build development assets
mix assets.deploy                 # Build production assets
mix test                          # Run unit/integration tests
MIX_ENV=test mix test.e2e         # Run E2E tests
mix format                        # Format Elixir code
mix lint                          # Run credo --strict and dialyzer
mix compile --warnings-as-errors  # Match the CI compile gate
```

## Hex Client Usage

Point Mix at a HexHub instance with `HEX_MIRROR`:

```bash
export HEX_MIRROR=http://localhost:4360
mix deps.get
```

For a production instance:

```bash
export HEX_MIRROR=https://hex.example.com
mix deps.get
```

HexHub supports both root-level Hex client routes and `/api` routes. The root-level routes are used for Mix compatibility, including package metadata, tarballs, release information, docs, and dependency resolution.

## Publishing Packages

Create an API key in the admin dashboard or through the API, then publish with the Hex client against your HexHub URL.

```bash
mix hex.repo add private http://localhost:4360
mix hex.user key generate --repo private
mix hex.publish package --repo private
```

If the deployment publishes a repository public key, pass it with `--public-key PATH` or `--fetch-public-key FINGERPRINT`.

Anonymous publishing can be enabled from the admin dashboard when the deployment intentionally allows unauthenticated package publishing.

## HTTP API

HexHub exposes Hex-compatible API endpoints under `/api` and selected root-level endpoints required by the Mix client.

Common endpoints:

- `GET /api/packages`
- `GET /api/packages/:name`
- `POST /api/packages/:name/releases`
- `GET /api/packages/:name/releases/:version`
- `POST /api/packages/:name/releases/:version/docs`
- `POST /api/packages/:name/releases/:version/retire`
- `GET /api/keys`
- `POST /api/keys`
- `GET /api/repos`

The OpenAPI document is available at `priv/static/openapi/hex-api.yaml` in the repository.

## Configuration

Production configuration is environment-driven.

| Variable | Description | Default |
| --- | --- | --- |
| `SECRET_KEY_BASE` | Phoenix secret key base | required in production |
| `PHX_HOST` | Public package/API hostname | `hex-hub.dev` |
| `PORT` | Public package/API port | `4360` |
| `ADMIN_PHX_HOST` | Admin dashboard hostname | `admin.hex-hub.dev` |
| `ADMIN_PORT` | Admin dashboard port | `4361` |
| `MNESIA_DIR` | Mnesia data directory | `mnesia` |
| `STORAGE_TYPE` | Storage backend: `local` or `s3` | `local` |
| `STORAGE_PATH` | Local package/docs storage path | `priv/storage` |
| `S3_BUCKET` | S3 bucket when `STORAGE_TYPE=s3` | unset |
| `S3_BUCKET_PATH` | Prefix inside the S3 bucket | `/` |
| `AWS_ACCESS_KEY_ID` | S3 access key | unset |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | unset |
| `AWS_REGION` | S3 region | `us-east-1` |
| `AWS_S3_HOST` | Custom S3-compatible endpoint host | unset |
| `AWS_S3_PORT` | Custom S3 endpoint port | `443` |
| `AWS_S3_SCHEME` | `http` or `https` | `https` |
| `AWS_S3_PATH_STYLE` | Enable path-style S3 requests | `false` |
| `UPSTREAM_ENABLED` | Enable upstream package proxying | `true` |
| `UPSTREAM_API_URL` | Upstream Hex API URL | `https://hex.pm` |
| `UPSTREAM_REPO_URL` | Upstream Hex repo URL | `https://repo.hex.pm` |
| `CLUSTERING_ENABLED` | Enable clustering | `false` |
| `MCP_ENABLED` | Enable MCP server | `false` |
| `MCP_REQUIRE_AUTH` | Require API key auth for MCP | `true` |
| `MCP_RATE_LIMIT` | MCP requests per hour per IP | `1000` |
| `LOG_CONSOLE_ENABLED` | Enable telemetry console logs | `true` |
| `LOG_CONSOLE_LEVEL` | Console log level | `info` |
| `LOG_FILE_ENABLED` | Enable telemetry file logs | `false` |
| `LOG_FILE_PATH` | Telemetry log file path | unset |

## Storage

Local storage is the default:

```bash
export STORAGE_TYPE=local
export STORAGE_PATH=/var/lib/hex_hub/storage
export MNESIA_DIR=/var/lib/hex_hub/mnesia
```

S3-compatible storage:

```bash
export STORAGE_TYPE=s3
export S3_BUCKET=hex-packages
export S3_BUCKET_PATH=/hex-hub
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
```

For MinIO or another S3-compatible service:

```bash
export AWS_S3_HOST=minio.example.com
export AWS_S3_PORT=9000
export AWS_S3_SCHEME=http
export AWS_S3_PATH_STYLE=true
```

## Production Release

```bash
MIX_ENV=prod mix assets.setup
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

SECRET_KEY_BASE="$(mix phx.gen.secret)" \
PHX_HOST=hex.example.com \
ADMIN_PHX_HOST=admin.hex.example.com \
MNESIA_DIR=/var/lib/hex_hub/mnesia \
STORAGE_PATH=/var/lib/hex_hub/storage \
_build/prod/rel/hex_hub/bin/hex_hub start
```

Keep `MNESIA_DIR` and the configured storage backend on durable storage and include both in backups.

## Docker

Prebuilt images are published to GitHub Container Registry:

```bash
docker pull ghcr.io/gsmlg-dev/hex-hub:main
```

Run a single-node local-storage deployment:

```bash
docker run -d \
  --name hex-hub \
  -p 4360:4360 \
  -p 4361:4361 \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=localhost \
  -e ADMIN_PHX_HOST=localhost \
  -e MNESIA_DIR=/data/mnesia \
  -e STORAGE_PATH=/data/storage \
  -v hex_hub_data:/data \
  ghcr.io/gsmlg-dev/hex-hub:main
```

## MCP Server

Enable the MCP server when AI clients need package search, release lookup, dependency, documentation, or repository tools.

```bash
export MCP_ENABLED=true
export MCP_REQUIRE_AUTH=true
export MCP_RATE_LIMIT=1000
```

Endpoints:

- `GET /mcp/health`
- `GET /mcp/tools`
- `GET /mcp/server-info`
- `POST /mcp`
- `WS /mcp/ws`

See `docs/mcp-deployment.md` for deployment details.

## Operational Docs

- `docs/docker.md` - Docker deployment examples
- `docs/hex-mirror.md` - `HEX_MIRROR` and upstream cache behavior
- `docs/clustering.md` - clustered Mnesia deployments
- `docs/mcp-deployment.md` - MCP server configuration and deployment

## Data Migrations

Mnesia schema changes must preserve existing data. Add migration functions in `lib/hex_hub/mnesia.ex`, transform old tuple shapes to the new shape, and run migrations during startup after table creation and before table waits. Do not recreate tables that may contain production data.

## License

MIT License. See `LICENSE` for details.
