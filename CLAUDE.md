# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HexHub is a **private hex package manager and hexdocs server** — a drop-in replacement for hex.pm. Built with Phoenix 1.8 and Elixir 1.15+, it uses Mnesia (no external database) and supports clustering for high availability.

## Commands

```bash
mix setup                    # Install deps + build assets
mix phx.server               # Start dev server (main: 4360, admin: 4361)
mix test                     # Run all tests
mix test path/to/test.exs    # Run single test file
mix test path/to/test.exs:42 # Run test at specific line
mix format                   # Format code
mix credo --strict           # Static analysis
mix dialyzer                 # Type checking (slow first run, PLT cached in priv/plts/)

# E2E tests (separate from unit tests, in e2e_test/ directory)
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs --only us1

# Assets (builds both main + admin apps)
mix assets.build             # Dev build
mix assets.deploy            # Production minified build
```

## Architecture

### Dual Web Endpoints

The app runs **two independent Phoenix endpoints** on separate ports:

- **`HexHubWeb`** (port 4360 dev) — Public API + HTML package browser. Routes in `lib/hex_hub_web/router.ex`. Serves the hex client protocol (binary protobuf registry at `/names`, `/versions`), REST API at `/api/*`, health checks, and MCP endpoints.
- **`HexHubAdminWeb`** (port 4361 dev) — Admin dashboard. Routes in `lib/hex_hub_admin_web/router.ex`. CRUD for packages, users, repositories, backups, upstream config.

Both endpoints are supervised independently in `lib/hex_hub/application.ex`.

### Router Pipelines (Main Web)

Key plug pipelines to understand when adding routes:
- `:api_auth` — Bearer token authentication + rate limiting (most API endpoints)
- `:api_auth_optional` — Allows anonymous access when anonymous publishing is enabled
- `:registry` — Binary protobuf format for hex client compatibility (no content-type filtering)
- `:require_write` — Authorization check for write operations

### Authentication Flow

1. Client sends `Authorization: Bearer <key>` header
2. `HexHubWeb.Plugs.Authenticate` extracts key → `HexHub.ApiKeys.validate_key/1`
3. `HexHub.ApiKeyCache` (GenServer + ETS) provides fast lookup
4. Conn gets `:current_user` assign

### Mnesia Database

- **No external database** — all data in Mnesia tables (15 tables defined in `lib/hex_hub/mnesia.ex`)
- All operations **must be wrapped in transactions**: `:mnesia.transaction(fn -> ... end)`
- Use `@table_name` module attributes for table references (pattern used across all context modules)
- Tables auto-initialize on first run; tests reset via `HexHub.Mnesia.reset_tables()`
- Dev data: `priv/mnesia/dev/`, Test data: `priv/mnesia/test/`
- Debug in IEx: `:mnesia.info()`, `:mnesia.table_info(:users, :all)`

### Storage Abstraction

All file storage (tarballs, docs) goes through `HexHub.Storage` — never access filesystem/S3 directly. Backend is configurable: local filesystem (`priv/storage/`) or S3-compatible.

### MCP Server

JSON-RPC 2.0 server for AI client integration. Conditionally started in supervision tree when `config :hex_hub, :mcp, enabled: true`. Endpoints: `POST /mcp`, `GET /mcp/tools`, `GET /mcp/server-info`. Can run with or without authentication (`require_auth: true/false`).

### Upstream Proxy

When a package isn't found locally, `HexHub.Upstream` transparently fetches from hex.pm (or configured upstream), caches it permanently. Configurable via `UPSTREAM_ENABLED` env var.

## Code Conventions

### Telemetry-First Logging

**Do NOT use `Logger` directly** for operational events. Emit telemetry events instead:

```elixir
# Correct
:telemetry.execute([:hex_hub, :package, :published], %{duration: ms}, %{package: name})

# Wrong
Logger.info("Package #{name} published")
```

Use `HexHub.Telemetry.log/4` helper for structured logging. Handlers in `lib/hex_hub/telemetry/` route events to console/file.

Exceptions: `Application.start/2` startup messages, rescue blocks where telemetry may not be available.

### Error Handling

Return `{:ok, result}` or `{:error, reason}` tuples consistently across all context modules.

### Test Helpers

`test/support/test_helpers.ex` provides: `create_user/1`, `setup_authenticated_user/1`, `authenticated_conn/2`, `create_package/1`, `create_test_tarball/3`. Tests in `test/support/conn_case.ex` auto-reset Mnesia + test storage before each test.

### Adding New API Endpoints

1. Add route in `lib/hex_hub_web/router.ex` (choose correct pipeline)
2. Create controller in `lib/hex_hub_web/controllers/api/`
3. Business logic in context module under `lib/hex_hub/`
4. Tests in `test/hex_hub_web/controllers/api/`
5. Update `hex-api.yaml` if it's a public API

## CI Pipeline

GitHub Actions runs: Compile (warnings-as-errors), Format Check, Credo (strict), Dialyzer, Tests, E2E Tests. All must pass. Dialyzer PLT is cached by OTP/Elixir version + mix.lock hash; warnings suppressed via `.dialyzer_ignore.exs`.

## Environment Variables

See `config/runtime.exs` for full list. Key ones:
- `SECRET_KEY_BASE`, `PHX_HOST` — Required in production
- `STORAGE_TYPE` (`local`/`s3`), `S3_BUCKET`, `AWS_*` — Storage config
- `UPSTREAM_ENABLED`, `UPSTREAM_URL` — Upstream proxy
- `CLUSTERING_ENABLED` — Mnesia clustering via libcluster
- `MCP_REQUIRE_AUTH`, `MCP_RATE_LIMIT` — MCP public access
- `LOG_CONSOLE_LEVEL`, `LOG_FILE_PATH` — Telemetry logging
