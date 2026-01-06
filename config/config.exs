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
config :hex_hub, :mcp,
  enabled: System.get_env("MCP_ENABLED", "false") == "true",
  websocket_path: System.get_env("MCP_WEBSOCKET_PATH", "/mcp/ws"),
  rate_limit: String.to_integer(System.get_env("MCP_RATE_LIMIT", "1000")),
  require_auth: System.get_env("MCP_REQUIRE_AUTH", "true") == "true",
  websocket_heartbeat: System.get_env("MCP_WEBSOCKET_HEARTBEAT", "true") == "true",
  heartbeat_interval: String.to_integer(System.get_env("MCP_HEARTBEAT_INTERVAL", "30000")),
  debug: System.get_env("MCP_DEBUG", "false") == "true"

config :bun,
  version: "1.2.13",
  hex_hub: [
    args: ~w(build assets/js/app.js --outdir=priv/static/assets),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => "#{Path.expand("../deps", __DIR__)}"}
  ],
  hex_hub_admin: [
    args: ~w(build assets/js/admin.js --outdir=priv/static/assets),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => "#{Path.expand("../deps", __DIR__)}"}
  ]

config :tailwind,
  version: "4.1.11",
  hex_hub: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ],
  hex_hub_admin: [
    args: ~w(
      --input=assets/css/admin.css
      --output=priv/static/assets/admin.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Telemetry-based logging configuration
config :hex_hub, :telemetry_logging,
  console: [enabled: true, level: :info],
  file: [enabled: false, path: nil, level: :debug]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

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
