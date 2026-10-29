ExUnit.start()

# Setup test storage directory
File.mkdir_p!("priv/test_storage")
Application.put_env(:hex_hub, :storage_path, "priv/test_storage")
Application.put_env(:hex_hub, :storage_type, :local)

# Configure upstream for testing
Application.put_env(:hex_hub, :upstream, enabled: true, url: "https://test.hex.pm")

# Configure MCP for testing
Application.put_env(:hex_hub, :mcp, enabled: true, require_auth: false)

# Start HexHub application for testing
{:ok, _} = Application.ensure_all_started(:hex_hub)

# Reset metadata using the configured backend. PostgreSQL tests need a dedicated database.
HexHub.Database.reset_tables()

# Ensure MCP server is started for tests
HexHub.MCP.Server.start_link([])
