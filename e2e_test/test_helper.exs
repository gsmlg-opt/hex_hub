# E2E Test Helper
# This file initializes the E2E test environment with isolated Mnesia and storage

# Configure endpoint BEFORE starting the application
# This enables the HTTP server with a dynamic port for E2E testing
endpoint_config = Application.get_env(:hex_hub, HexHubWeb.Endpoint, [])

http_config =
  endpoint_config
  |> Keyword.get(:http, [])
  |> Keyword.merge(ip: {127, 0, 0, 1}, port: 0)

Application.put_env(
  :hex_hub,
  HexHubWeb.Endpoint,
  Keyword.merge(endpoint_config,
    adapter: Gaoxy.PhoenixAdapter,
    http: http_config,
    server: true,
    secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64),
    url: [host: "localhost"],
    pubsub_server: HexHub.PubSub,
    live_view: [signing_salt: "e2e_test_salt"]
  )
)

# Start ExUnit
ExUnit.start(exclude: [:skip])

# Initialize Mnesia for E2E testing with a unique directory
:ok = Application.ensure_started(:mnesia)

# Stop Mnesia if running, create fresh schema
:mnesia.stop()
mnesia_dir = "Mnesia.e2e_test_#{System.unique_integer([:positive])}"
File.rm_rf!(mnesia_dir)
Application.put_env(:mnesia, :dir, String.to_charlist(mnesia_dir))
:mnesia.create_schema([node()])
:mnesia.start()

# Initialize Mnesia tables
HexHub.Mnesia.init()

# Setup isolated test storage directory
e2e_storage_path = "priv/e2e_test_storage_#{System.unique_integer([:positive])}"
File.mkdir_p!(e2e_storage_path)
Application.put_env(:hex_hub, :storage_path, e2e_storage_path)
Application.put_env(:hex_hub, :storage_type, :local)

# Configure upstream for E2E testing (real hex.pm)
Application.put_env(:hex_hub, :upstream,
  enabled: true,
  api_url: "https://hex.pm",
  repo_url: "https://repo.hex.pm",
  timeout: 30_000,
  retry_attempts: 3,
  retry_delay: 1_000
)

# Disable MCP for E2E tests
Application.put_env(:hex_hub, :mcp, enabled: false)

# Cleanup on exit
System.at_exit(fn _status ->
  # Clean up Mnesia directory
  File.rm_rf!(mnesia_dir)
  # Clean up storage directory
  File.rm_rf!(e2e_storage_path)
end)
