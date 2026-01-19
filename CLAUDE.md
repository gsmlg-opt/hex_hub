# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HexHub is a **complete private hex package manager and hexdocs server** built with Phoenix 1.8.0-rc.4 and Elixir 1.15+. It provides a **drop-in replacement for hex.pm** with complete API compatibility, using Mnesia for zero-database storage and clustering support for high availability.

### Architecture Highlights

**Dual Web Interface**: Main public API (`hex_hub_web`) + Admin dashboard (`hex_hub_admin_web`)
**MCP Server**: Complete Model Context Protocol implementation for AI client integration
**Mnesia Database**: No external database required, with clustering support for high availability
**Storage Abstraction**: Local filesystem or S3-compatible storage via `HexHub.Storage`
**Upstream Integration**: Transparent fallback to hex.pm or any hex-compatible repository
**Complete API**: 94 comprehensive tests with 100% endpoint coverage

## Key Architecture

- **Phoenix Framework 1.8.0-rc.4**: Web layer with LiveView for real-time features
- **MCP Server**: Model Context Protocol server for AI client integration
- **Mnesia**: In-memory distributed database (no PostgreSQL required)
- **Telemetry**: Event-driven observability (metrics + logging via `:telemetry`)
- **Tailwind CSS + DaisyUI**: Modern styling with responsive design
- **Bun**: JavaScript bundling and build tooling
- **Bandit**: High-performance HTTP server
- **Swoosh**: Email functionality
- **Libcluster**: Automatic cluster formation and discovery
- **Local/S3 Storage**: Flexible package and documentation storage

## Quick Start Commands

### Development Setup
```bash
# Install dependencies and setup (no database setup needed)
mix setup

# Start development server
mix phx.server

# Run comprehensive test suite (94 tests, 100% passing)
mix test

# Start with clustering
PORT=4000 NODE_NAME=hex_hub1 ./scripts/cluster.sh start
```

### Asset Management
```bash
# Build assets for development
mix assets.build

# Deploy/minify assets for production
mix assets.deploy

# Setup asset tools
mix assets.setup
```

### Testing & Quality
```bash
# Run all tests with coverage
mix test --cover

# Run specific test file
mix test test/hex_hub_web/controllers/api/package_controller_test.exs

# Run tests matching pattern
mix test --only user

# Format code
mix format

# Static analysis
mix credo

# Type checking
mix dialyzer

# Check dependency status
mix deps.tree

# Clean and recompile
mix deps.clean --build && mix deps.get && mix compile
```

## Project Structure

```
lib/
├── hex_hub/                    # Core business logic
│   ├── packages.ex            # Package publishing & management
│   ├── users.ex               # User management & authentication
│   ├── api_keys.ex            # API key generation & auth
│   ├── mnesia.ex              # Database schema & table definitions
│   ├── storage.ex             # Storage abstraction (local/S3)
│   ├── upstream.ex            # Upstream package fetching
│   ├── clustering.ex          # Mnesia cluster management
│   ├── telemetry.ex           # Telemetry events, metrics & logging
│   └── audit.ex               # Audit logging
├── hex_hub_web/               # Main web interface (public API)
│   ├── controllers/api/       # API controllers with authentication
│   ├── components/            # LiveView components
│   ├── plugs/                 # Authentication & rate limiting
│   └── router.ex             # API routes organization
├── hex_hub_admin_web/         # Admin dashboard
│   ├── controllers/           # Admin CRUD operations
│   ├── components/            # Admin LiveView components
│   └── router.ex             # Admin routes
├── hex_hub/mcp/               # MCP (Model Context Protocol) server
│   ├── server.ex              # Main MCP server implementation
│   ├── handler.ex             # JSON-RPC message handling
│   ├── transport.ex           # HTTP/WebSocket transport layer
│   ├── tools/                 # MCP tool implementations
│   │   ├── packages.ex        # Package management tools
│   │   ├── releases.ex        # Release management tools
│   │   ├── documentation.ex   # Documentation access tools
│   │   ├── dependencies.ex    # Dependency resolution tools
│   │   └── repositories.ex    # Repository management tools
│   ├── schemas.ex             # MCP JSON schemas
│   └── supervisor.ex          # MCP server supervision
```

## Key Files

- `mix.exs` - Dependencies and project configuration
- `hex-api.yaml` - Complete OpenAPI specification for Hex API
- `config/config.exs` - General configuration
- `config/clustering.exs` - Mnesia clustering configuration
- `lib/hex_hub/mnesia.ex` - Mnesia database setup and table definitions
- `lib/hex_hub/clustering.ex` - Cluster management logic
- `lib/hex_hub/storage.ex` - Storage abstraction (local/S3)
- `lib/hex_hub/mcp/server.ex` - MCP server implementation
- `scripts/cluster.sh` - Cluster management script

## Important Development Notes

### Mnesia Database
- **No external database required** - uses Mnesia for storage
- Tables auto-initialize on first run
- Data stored in `Mnesia.<node_name>/` directory
- Test data is isolated automatically
- Use `:mnesia.info()` in IEx for debugging

### Storage Architecture
- **Local storage** (default): `priv/storage/`
- **S3 storage** (production): Configure via environment variables
- Storage abstraction in `lib/hex_hub/storage.ex` handles both

### API Testing
- All endpoints require API key authentication
- Use `mix test` for comprehensive test coverage (94 tests)
- API tests in `test/hex_hub_web/controllers/api/`
- Test users and API keys auto-created in test setup

## Environment Configuration

### Development
- **Mnesia**: Automatic setup, RAM + disk storage
- **Storage**: Local filesystem at `priv/storage/`
- **Clustering**: Optional, via `CLUSTERING_ENABLED=true`

### Production
- **Mnesia**: Disk persistence with clustering
- **Storage**: Configurable (local/S3)
- **Clustering**: Automatic with libcluster

### Environment Variables
```bash
# Required
SECRET_KEY_BASE=your-64-byte-secret  # Generate with `mix phx.gen.secret`
PHX_HOST=your-domain.com             # Host for URL generation

# Optional
CLUSTERING_ENABLED=true              # Enable clustering
MNESIA_DIR=/app/mnesia              # Mnesia data directory
STORAGE_TYPE=local                  # or s3
S3_BUCKET=your-bucket               # S3 configuration

# S3 Configuration (when STORAGE_TYPE=s3)
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
AWS_S3_HOST=your-s3-host            # For S3-compatible services
AWS_S3_PORT=9000                     # Custom S3 port
AWS_S3_PATH_STYLE=true               # Required for MinIO

# Upstream Configuration
UPSTREAM_ENABLED=true                # Enable upstream package fetching
UPSTREAM_URL=https://hex.pm          # Upstream hex repository URL
UPSTREAM_API_KEY=your_api_key        # API key for private repositories (optional)
UPSTREAM_TIMEOUT=30000               # Request timeout in milliseconds
UPSTREAM_RETRY_ATTEMPTS=3            # Number of retry attempts
UPSTREAM_RETRY_DELAY=1000            # Delay between retries in milliseconds
```

## API Implementation Status ✅

### Completed Endpoints
- **Users**: Registration, authentication, profiles, password reset
- **Packages**: Publishing, retrieval, search, metadata
- **Releases**: Version management, retirement, documentation
- **Repositories**: Private/public repository management
- **API Keys**: Generation, management, authentication
- **Documentation**: Upload, serving, version management
- **Ownership**: Package ownership management

### Test Coverage ✅
- 94 comprehensive tests
- 100% API endpoint coverage
- Mnesia transaction testing
- Clustering and failover tests
- Security and authorization tests

## Advanced Features

### Mnesia Clustering
- **High Availability**: Automatic failover and data replication
- **Scalability**: Add nodes dynamically
- **Persistence**: Disk-based storage with RAM caching
- **Consistency**: Transactional guarantees

### Storage Options
- **Local Filesystem**: Default for development
- **S3 Compatible**: Production-ready with CDN support
- **Hybrid**: Mixed storage strategies

### Security
- **API Key Authentication**: Bearer token support
- **Basic Auth**: For API key creation
- **Rate Limiting**: Configurable per-endpoint
- **HTTPS Ready**: Production deployment ready

## Clustering Commands

### Development Cluster
```bash
# Start 3-node cluster
PORT=4000 NODE_NAME=hex_hub1 ./scripts/cluster.sh start
PORT=4001 NODE_NAME=hex_hub2 ./scripts/cluster.sh start  
PORT=4002 NODE_NAME=hex_hub3 ./scripts/cluster.sh start

# Join cluster
./scripts/cluster.sh join hex_hub1@127.0.0.1

# Check status
./scripts/cluster.sh status
```

### Production Cluster
```bash
# Docker deployment
docker-compose up -d

# Kubernetes
kubectl apply -f k8s/

# Build and deploy release
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
_build/prod/rel/hex_hub/bin/hex_hub start
```

## Monitoring & Debugging

### LiveDashboard
- Available at `/dev/dashboard` in development
- Mnesia-specific metrics and queries
- Cluster status and node health
- Real-time performance monitoring

### Health Checks
- `/health` - Basic health check
- `/health/ready` - Kubernetes readiness
- `/health/live` - Kubernetes liveness
- `/api/cluster/status` - Cluster status
- `/mcp/http` - MCP HTTP endpoint
- `/mcp/ws` - MCP WebSocket endpoint

## Performance Characteristics

- **Query Performance**: <50ms Mnesia queries
- **Horizontal Scaling**: Linear scaling with cluster nodes
- **Storage**: Efficient binary storage for packages/docs
- **Memory**: RAM + disk hybrid storage strategy

## Common Development Patterns

### Adding New API Endpoints
1. Define route in `lib/hex_hub_web/router.ex`
2. Create controller in `lib/hex_hub_web/controllers/api/`
3. Add business logic to appropriate context in `lib/hex_hub/`
4. Add tests in `test/hex_hub_web/controllers/api/`
5. Update `hex-api.yaml` if exposing public API

### Database Schema Changes
1. Modify table definitions in `lib/hex_hub/mnesia.ex`
2. Add migration logic for existing data
3. Update test fixtures in `test/support/`
4. Test with `mix test` (data automatically reset between tests)

### Adding New Storage Types
1. Implement storage callbacks in `lib/hex_hub/storage.ex`
2. Add configuration to `config/config.exs`
3. Add tests for new storage type
4. Update environment variable documentation

### Working with Mnesia

#### Database Operations
All Mnesia operations must be wrapped in transactions:
```elixir
:mnesia.transaction(fn ->
  :mnesia.write({:users, username, email, password_hash, now, now})
end)
```

#### Debugging Mnesia
```elixir
# In IEx console
:mnesia.info()                    # Show database info
:mnesia.table_info(:users, :all)  # Show table details
:qlc.q([u || u <- :mnesia.table(:users)])  # Query table
```

#### Testing with Mnesia
Tests automatically reset Mnesia between runs:
```elixir
# In test setup
HexHub.Mnesia.reset_test_store()  # Clean test database
```

### MCP Server Testing
MCP functionality includes comprehensive test coverage:
```elixir
# Run MCP-specific tests
mix test test/hex_hub/mcp/

# Test MCP tools
mix test test/hex_hub/mcp/tools/

# Test MCP server integration
mix test test/hex_hub/mcp/server_test.exs
```

### E2E Package Publishing Tests
End-to-end tests for `mix hex.publish` functionality:
```bash
# Run all E2E publish tests
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs

# Run specific user story tests
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs --only us1  # Basic publishing
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs --only us2  # Authentication
MIX_ENV=test mix test.e2e e2e_test/publish_test.exs --only us3  # Version management
```

**Test Coverage**:
- US1: Basic package publishing with valid credentials
- US2: Authentication failure with no/invalid/read-only API keys
- US3: Multiple version publishing and retrieval

**Key Components**:
- `e2e_test/support/publish_helper.ex` - Helpers for hex publish environment, API keys, fixtures
- `e2e_test/support/server_helper.ex` - Dynamic server start with port allocation
- `e2e_test/fixtures/publish_project/` - Fixture package for testing

### Upstream Package Fetching

HexHub automatically fetches packages from upstream when not found locally, creating a transparent caching proxy for hex.pm or any hex-compatible repository.

**Configuration**: Enable/disable via `UPSTREAM_ENABLED` environment variable
**API Key Support**: Optional `UPSTREAM_API_KEY` for authenticating with private repositories
**Behavior**: Packages fetched once are cached permanently for future requests
**Monitoring**: All upstream requests tracked with telemetry metrics
**Retry Logic**: Automatic retry with exponential backoff for network failures
**Authentication**: Uses Bearer token authentication when API key is configured

### Authentication Patterns

**API Key Authentication**: Bearer token required for all API endpoints
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" /api/packages
```

**Permission Levels**: Read/write access separated by API key permissions
**Rate Limiting**: Configurable per-endpoint rate limiting
**Security**: All secrets hashed with bcrypt

### MCP Server Development

The MCP (Model Context Protocol) server provides AI clients with comprehensive package management capabilities:

**Architecture**: JSON-RPC server with HTTP/WebSocket transport
**Tools Available**: Package search, release management, documentation access, dependency resolution, repository management
**Configuration**: Enable via `config :hex_hub, :mcp, enabled: true`
**Deployment**: See `MCP_DEPLOYMENT.md` for detailed configuration and usage

**Key MCP Files**:
- `lib/hex_hub/mcp/server.ex` - Main MCP server GenServer
- `lib/hex_hub/mcp/handler.ex` - JSON-RPC request handling
- `lib/hex_hub/mcp/transport.ex` - HTTP/WebSocket transport layer
- `lib/hex_hub/mcp/tools/` - MCP tool implementations

**Public MCP API**:
The MCP API can be configured for public (unauthenticated) access to allow AI clients to query package information:

```bash
# Enable public access (no authentication required for read-only operations)
export MCP_REQUIRE_AUTH=false
export MCP_RATE_LIMIT=100  # requests per hour per IP
```

Public endpoints:
- `GET /mcp/health` - Health check
- `GET /mcp/tools` - List available tools
- `GET /mcp/server-info` - Server capabilities
- `POST /mcp` - JSON-RPC requests for package queries

Rate limiting: IP-based rate limiting protects against abuse. Returns HTTP 429 with `retry-after` header when exceeded.

See `specs/008-mcp-public-api/quickstart.md` for detailed usage examples.

### Development Patterns

**Always Use Storage Abstraction**: Never access storage directly, use `HexHub.Storage`
**Transaction Safety**: Wrap all Mnesia operations in transactions
**Error Handling**: Use consistent error response formats
**Telemetry-First Logging**: Use telemetry events instead of direct Logger calls (see below)

### Telemetry-First Logging (Constitution Principle VII)

Application code MUST NOT use `Logger` directly for operational logging. All loggable events
MUST be emitted as telemetry events via `:telemetry.execute/3`. Logging output is handled by
attaching telemetry handlers that route events to appropriate destinations.

**Correct Pattern**:
```elixir
# Emit telemetry event for logging
:telemetry.execute([:hex_hub, :package, :published], %{duration: duration_ms}, %{
  package: name,
  version: version,
  user: username
})
```

**Incorrect Pattern**:
```elixir
# DO NOT use Logger directly for operational events
Logger.info("Package #{name} published")
```

**Handler Setup**: Telemetry handlers are registered in the application supervision tree:
- Console logging via `Logger` (configurable log level)
- Optional file logging (when configured via environment)
- External systems integration (metrics services, log aggregators)

**Exceptions** - Direct `Logger` usage is permitted only for:
- Application startup/shutdown messages in `Application.start/2`
- Debugging during development (MUST be removed before merge)
- Error rescue blocks where telemetry might not be available

**Rationale**: Telemetry-first logging provides:
1. Decoupled event emission from output handling
2. Consistent event structure across the application
3. Easy integration with external observability systems
4. Ability to enable/disable specific log streams without code changes
5. Metrics and logging from the same event source

**Key Files**:
- `lib/hex_hub/telemetry.ex` - Telemetry metrics, event definitions, and tracking functions

## Active Technologies
- Elixir 1.15+ / OTP 26+ + `:telemetry` (already in project), `Logger` (Elixir stdlib) (001-telemetry-logging)
- N/A (logging to console/files, not database) (001-telemetry-logging)
- Elixir 1.15+ (matching project requirements) + ExUnit, Hex client (mix hex.publish), existing E2E infrastructure (002-hex-publish-e2e)
- Mnesia (via existing HexHub.Storage abstraction) for test data (002-hex-publish-e2e)
- Elixir 1.15+ / OTP 26+ + Phoenix 1.8+, Mnesia (built-in), DaisyUI/Tailwind CSS (003-browse-packages)
- Mnesia (`:packages`, `:package_releases`, `:package_downloads` tables) (003-browse-packages)
- Elixir 1.15+ / OTP 26+ + Phoenix 1.8+, Tailwind CSS, DaisyUI, YamlElixir (for OpenAPI parsing) (004-api-docs)
- N/A (static documentation content rendered from templates and hex-api.yaml) (004-api-docs)
- Mnesia (`:packages`, `:package_releases` tables) + HexHub.Storage abstraction for tarballs (005-admin-package-management)
- Mnesia (`:system_settings` or `:publish_configs` table for setting, existing `:users` table for anonymous user) (006-anonymous-publish-config)
- Elixir 1.15+ / OTP 26+ + Phoenix 1.8+, Mnesia (built-in), :erl_tar (Erlang stdlib) (007-admin-backup)
- Mnesia for metadata, HexHub.Storage for package tarballs, local filesystem for backup archives (007-admin-backup)
- Elixir 1.15+ / OTP 26+ + Phoenix 1.8+, Mnesia, `:telemetry` (008-mcp-public-api)
- Mnesia (existing `:packages`, `:package_releases` tables) (008-mcp-public-api)

## Recent Changes
- 001-telemetry-logging: Added Elixir 1.15+ / OTP 26+ + `:telemetry` (already in project), `Logger` (Elixir stdlib)
