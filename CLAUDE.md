# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HexHub is a **private hex package manager and hexdocs server** — a drop-in replacement for hex.pm. Built with Phoenix 1.8 and Elixir 1.15+, it uses Mnesia (no external database) and supports clustering for high availability.

**Status**: Preparing for first release. Data migrations are now **required** — existing Mnesia data must be preserved across schema changes.

## Commands

```bash
mix setup                    # Install deps + build assets
mix phx.server               # Start dev server (main: 4360, admin: 4361)
mix test                     # Run all tests
mix test path/to/test.exs    # Run single test file
mix test path/to/test.exs:42 # Run test at specific line
mix format                   # Format code
mix lint                     # Runs credo --strict + dialyzer (defined in mix.exs aliases)
mix credo --strict           # Static analysis only
mix dialyzer                 # Type checking only (slow first run, PLT cached in priv/plts/)
mix compile --warnings-as-errors  # CI enforces this — check before pushing

# E2E tests (separate from unit tests, in e2e_test/ directory)
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs --only us1

# Assets (Tailwind standalone CLI + Bun bundler, builds both main + admin apps)
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

**Important**: Many API routes are intentionally duplicated at both root level (`/packages/:name/...`) and under `/api/` prefix (`/api/packages/:name/...`). Root-level routes exist for `HEX_MIRROR`/`HEX_API_URL` compatibility with the Mix client. When adding new API endpoints, add them under `/api/` and duplicate at root level only if needed for hex client compatibility.

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

### Mnesia Data Migrations

Since the first release, **schema changes require migrations** — never recreate tables with existing data. Mnesia has no built-in migration framework, so migrations are manual functions in `lib/hex_hub/mnesia.ex`.

**Existing pattern**: `migrate_package_source_field/0` shows the approach — check `tuple_size` of existing records, transform in a transaction, write back the new tuple. Migrations run in `init/0` after table creation.

**When adding a field to a Mnesia table**:
1. Add the new attribute to the table definition in `create_tables/0`
2. Write a migration function that transforms existing records (old tuple size → new tuple with default value)
3. Call the migration from `init/0` after `create_tables()` and before `wait_for_tables()`
4. Use `:mnesia.transform_table/3` for attribute list changes, or manual foldl+rewrite for data transforms
5. Test both fresh creation and migration from the previous schema

**Important**: Mnesia tables are tuples keyed by `{table_name, key, ...attributes}`. When you add a field, existing records keep the old tuple size. Always check `tuple_size` to detect records needing migration.

### Storage Abstraction

All file storage (tarballs, docs) goes through `HexHub.Storage` — never access filesystem/S3 directly. Backend is configurable: local filesystem (`priv/storage/`) or S3-compatible. Storage config is persisted to Mnesia (`:storage_configs` table) and synced to Application env on startup via `HexHub.StorageConfig`.

**Directory structure** — files are organized by source, type, and package name:

```
storage/
  hosted/                          # locally published packages
    packages/phoenix/phoenix-1.8.1.tar.gz
    docs/phoenix/phoenix-1.8.1.tar.gz
  cached/                          # fetched from upstream
    packages/jason/jason-1.4.1.tar.gz
    docs/jason/jason-1.4.1.tar.gz
```

Use `Storage.generate_package_key/3` and `Storage.generate_docs_key/3` to build keys — never construct paths manually. The `source` parameter (`:hosted` | `:cached`) maps from Mnesia's package `:source` field (`:local` | `:cached`) via `Packages.get_package_source/1`.

### MCP Server

JSON-RPC 2.0 server for AI client integration. Conditionally started in supervision tree when `config :hex_hub, :mcp, enabled: true`. Endpoints: `POST /mcp`, `GET /mcp/tools`, `GET /mcp/server-info`. Can run with or without authentication (`require_auth: true/false`).

### Upstream Proxy

When a package isn't found locally, `HexHub.Upstream` transparently fetches from hex.pm (or configured upstream), caches it permanently. Configurable via `UPSTREAM_ENABLED` env var.

## UI Libraries

The project uses the **DuskMoon UI** component ecosystem:

- **`phoenix_duskmoon`** — Phoenix LiveView component library (Hex package). Provides `dm_*` components for templates. Use this for all server-rendered UI components.
- **`@duskmoon-dev/core`** — CSS component library (npm). Base design system with utility classes and theme support.
- **`@duskmoon-dev/css-art`** — Pure CSS art components (npm). Decorative visual elements rendered entirely in CSS.
- **`@duskmoon-dev/elements`** — Web Components library (npm). Custom elements (`<el-dm-*>`) for interactive client-side UI.
- **`@duskmoon-dev/art-elements`** — CSS art as custom elements (npm). Web component wrappers for CSS art.

**When building UI**: Use `phoenix_duskmoon` `dm_*` components in HEEx templates. For client-side interactivity, use `@duskmoon-dev/elements` custom elements. Style with `@duskmoon-dev/core` CSS classes. Do not introduce other CSS frameworks or component libraries.

**Issues & feature requests**: If you encounter bugs or need new features in any DuskMoon UI library, file an issue in the corresponding GitHub repo with the label `internal request`:
- `phoenix_duskmoon` — https://github.com/gsmlg-dev/phoenix_duskmoon/issues
- `@duskmoon-dev/core` — https://github.com/aspect-build/aspect-frameworks/issues (TBD — confirm repo)
- `@duskmoon-dev/css-art` — https://github.com/aspect-build/aspect-frameworks/issues (TBD — confirm repo)
- `@duskmoon-dev/elements` — https://github.com/aspect-build/aspect-frameworks/issues (TBD — confirm repo)
- `@duskmoon-dev/art-elements` — https://github.com/aspect-build/aspect-frameworks/issues (TBD — confirm repo)

## Code Conventions

### Telemetry-First Logging

**Do NOT use `Logger` directly** for operational events. Use the `HexHub.Telemetry.log/4` helper:

```elixir
# Correct — use the telemetry helper with category and metadata
HexHub.Telemetry.log(:info, :package, "Package published", %{name: name, version: version})
HexHub.Telemetry.log(:warning, :auth, "Authentication failed", %{reason: "invalid_token"})

# Wrong — never call Logger directly for operational events
Logger.info("Package #{name} published")
```

Categories: `:api`, `:upstream`, `:storage`, `:auth`, `:package`, `:mcp`, `:cluster`, `:config`, `:user`, `:backup`, `:general`. Handlers in `lib/hex_hub/telemetry/` route events to console/file.

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
- `STORAGE_TYPE` (`local`/`s3`), `S3_BUCKET`, `S3_BUCKET_PATH`, `AWS_*` — Storage config
- `UPSTREAM_ENABLED`, `UPSTREAM_URL` — Upstream proxy
- `CLUSTERING_ENABLED` — Mnesia clustering via libcluster
- `MCP_REQUIRE_AUTH`, `MCP_RATE_LIMIT` — MCP public access
- `LOG_CONSOLE_LEVEL`, `LOG_FILE_PATH` — Telemetry logging
