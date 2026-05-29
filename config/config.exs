import Config

# Register custom MIME types for Hex client compatibility
config :mime, :types, %{
  "application/vnd.hex+erlang" => ["hex+erlang"]
}

config :hex_hub,
  generators: [timestamp_type: :utc_datetime],
  backup_path: "priv/backups",
  backup_retention_days: 30

config :hex_hub, HexHubWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HexHubWeb.ErrorHTML, json: HexHubWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HexHub.PubSub,
  live_view: [signing_salt: "y6PnerOV"]

config :hex_hub, HexHubAdminWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HexHubAdminWeb.ErrorHTML, json: HexHubAdminWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HexHub.PubSub,
  live_view: [signing_salt: "y6PnerOV"]

config :hex_hub, HexHub.Mailer, adapter: Swoosh.Adapters.Local

# MCP (Model Context Protocol) configuration
#
# MCP provides a JSON-RPC 2.0 interface for AI clients to interact with HexHub.
#
# Environment variables:
#   MCP_ENABLED       - Enable/disable MCP server (default: "false")
#   MCP_REQUIRE_AUTH  - Require API key authentication (default: "true")
#                       Set to "false" for public read-only access to package info
#   MCP_RATE_LIMIT    - Requests per hour per IP (default: "1000")
#                       Rate limiting protects against abuse when auth is disabled
#   MCP_DEBUG         - Enable debug logging (default: "false")
#
# Public deployment example:
#   MCP_ENABLED=true MCP_REQUIRE_AUTH=false MCP_RATE_LIMIT=100 ./bin/hex_hub start
#
# Endpoints (when enabled):
#   GET  /mcp/health      - Health check
#   GET  /mcp/tools       - List available tools
#   GET  /mcp/server-info - Server capabilities
#   POST /mcp             - JSON-RPC requests
#   WS   /mcp/ws          - WebSocket transport
#
config :hex_hub, :mcp,
  enabled: System.get_env("MCP_ENABLED", "false") == "true",
  websocket_path: System.get_env("MCP_WEBSOCKET_PATH", "/mcp/ws"),
  rate_limit: String.to_integer(System.get_env("MCP_RATE_LIMIT", "1000")),
  require_auth: System.get_env("MCP_REQUIRE_AUTH", "true") == "true",
  websocket_heartbeat: System.get_env("MCP_WEBSOCKET_HEARTBEAT", "true") == "true",
  heartbeat_interval: String.to_integer(System.get_env("MCP_HEARTBEAT_INTERVAL", "30000")),
  debug: System.get_env("MCP_DEBUG", "false") == "true"

config :volt,
  resolve_dirs: ["node_modules", "deps"],
  target: :es2020,
  sourcemap: :hidden

config :volt, :hex_hub,
  entry: "assets/js/app.js",
  outdir: "priv/static/assets/public",
  root: "assets",
  asset_url_prefix: "/assets/public",
  tailwind: [
    css: "assets/css/app.css",
    sources: [
      %{base: "lib/hex_hub_web", pattern: "**/*.{ex,heex}"},
      %{base: "lib/hex_hub", pattern: "**/*.{ex,heex}"},
      %{base: "deps/phoenix_duskmoon/lib/phoenix_duskmoon", pattern: "**/*.{ex,heex}"},
      %{base: "assets", pattern: "**/*.{js,css}"}
    ]
  ],
  server: [
    prefix: "/assets/public",
    watch_dirs: ["lib/hex_hub_web", "lib/hex_hub", "assets"]
  ]

config :volt, :hex_hub_admin,
  entry: "assets/js/admin.js",
  outdir: "priv/static/assets/admin",
  root: "assets",
  asset_url_prefix: "/assets/admin",
  tailwind: [
    css: "assets/css/admin.css",
    sources: [
      %{base: "lib/hex_hub_admin_web", pattern: "**/*.{ex,heex}"},
      %{base: "lib/hex_hub", pattern: "**/*.{ex,heex}"},
      %{base: "deps/phoenix_duskmoon/lib/phoenix_duskmoon", pattern: "**/*.{ex,heex}"},
      %{base: "assets", pattern: "**/*.{js,css}"}
    ]
  ],
  server: [
    prefix: "/assets/admin",
    watch_dirs: ["lib/hex_hub_admin_web", "lib/hex_hub", "assets"]
  ]

# Telemetry-based logging configuration
config :hex_hub, :telemetry_logging,
  console: [enabled: true, level: :info],
  file: [enabled: false, path: nil, level: :debug]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Req as HTTP client for ExAws (replaces hackney)
config :ex_aws, http_client: ExAws.Request.Req

config :phoenix, :json_library, Jason

# Upstream configuration (stored in Mnesia database)
config :hex_hub, :upstream,
  enabled: true,
  api_url: "https://hex.pm",
  repo_url: "https://repo.hex.pm",
  timeout: 30_000,
  retry_attempts: 3,
  retry_delay: 1_000

import_config "#{config_env()}.exs"
import_config "clustering.exs"
