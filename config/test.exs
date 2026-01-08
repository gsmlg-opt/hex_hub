import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hex_hub, HexHubWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "x2KKtgZ09R+tkr1nKiJqCBfaVPNBCFhsUvopCd82COii3ZqS13u4TQQcwfQULNNy",
  server: false

config :hex_hub, HexHubAdminWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base:
    "test_admin_secret_key_base_1234567890abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  server: false

# In test we don't send emails
config :hex_hub, HexHub.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Test storage configuration
config :hex_hub,
  storage_type: :local,
  storage_path: "priv/test_storage",
  mnesia_dir: "priv/mnesia/test"

# Mnesia directory for test
config :mnesia, dir: ~c"priv/mnesia/test"
