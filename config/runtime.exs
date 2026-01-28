import Config

# Telemetry logging runtime configuration (applies to all environments)
telemetry_console_enabled = System.get_env("LOG_CONSOLE_ENABLED", "true") == "true"
telemetry_console_level = String.to_existing_atom(System.get_env("LOG_CONSOLE_LEVEL", "info"))
telemetry_file_enabled = System.get_env("LOG_FILE_ENABLED", "false") == "true"
telemetry_file_path = System.get_env("LOG_FILE_PATH")
telemetry_file_level = String.to_existing_atom(System.get_env("LOG_FILE_LEVEL", "debug"))

config :hex_hub, :telemetry_logging,
  console: [enabled: telemetry_console_enabled, level: telemetry_console_level],
  file: [enabled: telemetry_file_enabled, path: telemetry_file_path, level: telemetry_file_level]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "hex-hub.dev"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :hex_hub, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :hex_hub, HexHubWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  host = System.get_env("ADMIN_PHX_HOST") || "admin.hex-hub.dev"
  port = String.to_integer(System.get_env("ADMIN_PORT") || "4001")

  config :hex_hub, HexHubAdminWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Storage configuration
  storage_type =
    case System.get_env("STORAGE_TYPE", "local") do
      "s3" -> :s3
      _ -> :local
    end

  config :hex_hub,
    env: :prod,
    storage_type: storage_type,
    storage_path: System.get_env("STORAGE_PATH", "priv/storage"),
    mnesia_dir: System.get_env("MNESIA_DIR", "mnesia"),
    s3_bucket: System.get_env("S3_BUCKET")

  # S3 configuration (when STORAGE_TYPE=s3)
  if storage_type == :s3 do
    s3_config = [
      scheme: if(System.get_env("AWS_S3_SCHEME") == "http", do: "http://", else: "https://"),
      host: System.get_env("AWS_S3_HOST"),
      port: String.to_integer(System.get_env("AWS_S3_PORT", "443"))
    ]

    # Add path_style option for MinIO/LocalStack compatibility
    s3_config =
      if System.get_env("AWS_S3_PATH_STYLE", "false") == "true" do
        Keyword.put(s3_config, :path_style, true)
      else
        s3_config
      end

    config :ex_aws,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION", "us-east-1")

    config :ex_aws, :s3, s3_config
  end
end
