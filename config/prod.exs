import Config

config :hex_hub, HexHubWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
config :hex_hub, HexHubAdminWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Production S3 Configuration
config :hex_hub,
  storage_type: System.get_env("STORAGE_TYPE", "local") |> String.to_atom(),
  s3_bucket: System.get_env("S3_BUCKET"),
  s3_bucket_path: System.get_env("S3_BUCKET_PATH", "/"),
  s3_region: System.get_env("AWS_REGION", "us-east-1")

# S3 Configuration for production
config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1")

config :ex_aws, :s3,
  scheme: System.get_env("AWS_S3_SCHEME", "https://"),
  host: System.get_env("AWS_S3_HOST"),
  port: if(port = System.get_env("AWS_S3_PORT"), do: String.to_integer(port), else: 443),
  path_style: System.get_env("AWS_S3_PATH_STYLE", "false") == "true"

# Production upstream configuration
config :hex_hub, :upstream,
  enabled: System.get_env("UPSTREAM_ENABLED", "true") == "true",
  api_url: System.get_env("UPSTREAM_API_URL", "https://hex.pm"),
  repo_url: System.get_env("UPSTREAM_REPO_URL", "https://repo.hex.pm"),
  timeout: String.to_integer(System.get_env("UPSTREAM_TIMEOUT", "30000")),
  retry_attempts: String.to_integer(System.get_env("UPSTREAM_RETRY_ATTEMPTS", "3")),
  retry_delay: String.to_integer(System.get_env("UPSTREAM_RETRY_DELAY", "1000"))
