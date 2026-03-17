defmodule HexHubWeb.Router do
  use HexHubWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HexHubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "hex+erlang"]
  end

  pipeline :docs_assets do
    plug :accepts, ~w(*)
  end

  pipeline :api_cached do
    plug :accepts, ["json", "hex+erlang"]
    plug HexHubWeb.Plugs.ETag
  end

  pipeline :api_auth do
    plug :accepts, ["json", "hex+erlang"]
    plug HexHubWeb.Plugs.HexFormat
    plug HexHubWeb.Plugs.Authenticate
    plug HexHubWeb.Plugs.RateLimit
  end

  # Pipeline for optional authentication (supports anonymous publishing when enabled)
  pipeline :api_auth_optional do
    plug :accepts, ["json", "hex+erlang"]
    plug HexHubWeb.Plugs.HexFormat
    plug HexHubWeb.Plugs.OptionalAuthenticate
    plug HexHubWeb.Plugs.RateLimit
  end

  pipeline :require_write do
    plug HexHubWeb.Plugs.Authorize, "write"
  end

  # Pipeline for binary registry data (protobuf)
  # No JSON accept header - accepts any content type
  pipeline :registry do
    plug :accepts, ["*/*"]
  end

  # Browser routes - must come FIRST so HTML requests match before API routes
  # The :browser pipeline only accepts ["html"], so API clients won't match these
  scope "/", HexHubWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Documentation routes
    get "/docs", DocsController, :index
    get "/docs/getting-started", DocsController, :getting_started
    get "/docs/publishing", DocsController, :publishing
    get "/docs/api-reference", DocsController, :api_reference
    get "/docs/mcp", DocsController, :mcp

    # Package browsing routes (HTML interface)
    get "/packages", PackageController, :index
    get "/packages/:name", PackageController, :show
    get "/packages/:name/docs", PackageController, :docs
    get "/packages/:name/:version/docs", PackageController, :docs

    # Legacy redirects for backward compatibility
    get "/browse", PackageController, :redirect_to_packages
    get "/package/:name", PackageController, :redirect_to_package
  end

  # Badge route for package version badges (SVG)
  scope "/", HexHubWeb do
    pipe_through :docs_assets

    get "/packages/:name/badge.svg", BadgeController, :show
  end

  # Package documentation asset routes (JS, CSS, images, etc.)
  # These need their own scope without the browser pipeline's content-type restrictions
  scope "/", HexHubWeb do
    pipe_through :docs_assets

    get "/packages/:name/docs/*page", PackageController, :docs
    get "/packages/:name/:version/docs/*page", PackageController, :docs
  end

  # Hex registry endpoints for HEX_MIRROR compatibility
  # These serve gzipped protobuf data that the Hex client expects
  # Note: /packages/:name is handled by PackageController which dispatches based on Accept header
  scope "/", HexHubWeb.API do
    pipe_through :registry

    # Registry endpoints (gzipped protobuf format)
    get "/names", RegistryController, :names
    get "/versions", RegistryController, :versions

    # Hex client version check endpoints
    # Returns empty CSV since Hex updates should come from official hex.pm
    get "/installs/hex-1.x.csv", InstallsController, :hex_csv
    get "/installs/hex-1.x.csv.signed", InstallsController, :hex_csv_signed
  end

  # API routes at root level for HEX_MIRROR compatibility (no /api prefix)
  # NOTE: These routes are intentionally duplicated at /api/* for standard API access
  # This root-level scope is specifically for Mix clients using HEX_MIRROR environment variable
  # Note: /packages and /packages/:name are browser routes (HTML), use /api/* for JSON
  scope "/", HexHubWeb.API do
    pipe_through :api_cached

    # Release and repo endpoints for Mix/HEX_MIRROR support (with caching)
    # Note: /packages is browser route, use /api/packages for JSON list
    get "/packages/:name/releases/:version", ReleaseController, :show
    get "/repos", RepositoryController, :list
    get "/repos/:name", RepositoryController, :show

    # Download endpoints (public, with upstream fallback)
    get "/packages/:name/releases/:version/download", DownloadController, :package
    get "/packages/:name/releases/:version/docs/download", DownloadController, :docs
    # Tarballs endpoint for Mix compatibility (HEX_MIRROR support)
    get "/tarballs/:tarball", DownloadController, :tarball
    # Installs endpoint for Mix dependency resolution
    get "/installs/:elixir_version/:requirements", PackageController, :installs
  end

  scope "/", HexHubWeb.API do
    pipe_through :api

    # Non-cached endpoints
    post "/users", UserController, :create
  end

  # Root-level authenticated routes for HEX_API_URL compatibility
  scope "/", HexHubWeb.API do
    pipe_through [:api_auth]

    # Authenticated package owners (read operations)
    get "/packages/:name/owners", OwnerController, :index
  end

  # Root-level publish routes with optional auth (supports anonymous publishing)
  scope "/", HexHubWeb.API do
    pipe_through [:api_auth_optional, :require_write]

    # Package publishing (supports anonymous when enabled)
    post "/publish", ReleaseController, :publish
    post "/packages/:name/releases", ReleaseController, :publish
  end

  # Health check endpoints for monitoring
  scope "/health", HexHubWeb do
    pipe_through :api

    get "/", HealthController, :index
    get "/ready", HealthController, :readiness
    get "/live", HealthController, :liveness
  end

  # Cluster management endpoints
  scope "/api", HexHubWeb do
    pipe_through :api

    get "/cluster/status", ClusterController, :status
    post "/cluster/join", ClusterController, :join
    post "/cluster/leave", ClusterController, :leave
  end

  # MCP (Model Context Protocol) endpoints
  # Routes are always defined, but controllers check if MCP is enabled at runtime
  scope "/mcp", HexHubWeb do
    pipe_through :api

    # MCP HTTP endpoints
    post "/", MCPController, :handle_request
    get "/tools", MCPController, :list_tools
    get "/server-info", MCPController, :server_info
    get "/health", MCPController, :health
  end

  # MCP WebSocket endpoint
  scope "/" do
    pipe_through :api

    # Commented out WebSocket for now - needs proper Phoenix.Socket setup
    # if function_exported?(Phoenix.Endpoint, :socket, 3) do
    #   socket "/mcp/ws", HexHub.MCP.WebSocket,
    #     websocket: [
    #       connect_info: [:req_headers, :query_params, :peer_data],
    #       timeout: 60_000
    #     ]
    # end
  end

  # API routes matching hex-api.yaml specification (with /api prefix)
  # NOTE: These routes are intentionally duplicated from root-level routes above
  # This /api/* scope is for standard REST API clients (curl, HTTPoison, etc.)
  scope "/api", HexHubWeb.API do
    pipe_through :api_cached

    # Public endpoints (with caching)
    get "/packages", PackageController, :list
    get "/packages/:name", PackageController, :show
    get "/packages/:name/releases/:version", ReleaseController, :show
    get "/repos", RepositoryController, :list
    get "/repos/:name", RepositoryController, :show

    # Search endpoints
    get "/packages/search", SearchController, :search
    get "/packages/suggest", SearchController, :suggest
    get "/packages/search/by/:field", SearchController, :search_by_field

    # Download endpoints (public, with upstream fallback)
    get "/packages/:name/releases/:version/download", DownloadController, :package
    get "/packages/:name/releases/:version/docs/download", DownloadController, :docs
    # Tarballs endpoint for Mix compatibility (HEX_MIRROR support)
    get "/tarballs/:tarball", DownloadController, :tarball
    # Installs endpoint for Mix dependency resolution
    get "/installs/:elixir_version/:requirements", PackageController, :installs
  end

  scope "/api", HexHubWeb.API do
    pipe_through :api

    # Non-cached endpoints
    post "/users", UserController, :create
  end

  # Authenticated API routes
  scope "/api", HexHubWeb.API do
    pipe_through [:api_auth]

    # Authenticated users endpoints (me MUST come before :username_or_email)
    get "/users/me", UserController, :me
    post "/users/:username_or_email/reset", UserController, :reset

    # Authenticated package management (read operations)
    get "/packages/:name/owners", OwnerController, :index

    # API Keys endpoints (read operations)
    get "/keys", KeyController, :list
    get "/keys/:name", KeyController, :show

    # Two-Factor Authentication endpoints
    get "/auth/totp", TwoFactorController, :setup
    post "/auth/totp", TwoFactorController, :enable
    delete "/auth/totp", TwoFactorController, :disable
    post "/auth/totp/verify", TwoFactorController, :verify
    post "/auth/totp/recovery", TwoFactorController, :verify_recovery
    post "/auth/totp/recovery/regenerate", TwoFactorController, :regenerate_recovery_codes

    # Retirement info endpoints (read operations)
    get "/packages/:name/releases/:version/retire", RetirementController, :show
    get "/packages/:name/retired", RetirementController, :index
  end

  # Publishing routes with optional auth (supports anonymous publishing when enabled)
  scope "/api", HexHubWeb.API do
    pipe_through [:api_auth_optional, :require_write]

    # Package publishing (supports anonymous when enabled)
    post "/publish", ReleaseController, :publish
    # Alternative publish endpoint used by hex client
    post "/packages/:name/releases", ReleaseController, :publish

    # Docs publishing (supports anonymous when enabled, part of mix hex.publish flow)
    post "/packages/:name/releases/:version/docs", DocsController, :publish
  end

  # Authenticated API routes requiring write permissions (always require auth)
  scope "/api", HexHubWeb.API do
    pipe_through [:api_auth, :require_write]

    # Package retirement (requires authentication)
    post "/packages/:name/releases/:version/retire", RetirementController, :retire
    delete "/packages/:name/releases/:version/retire", RetirementController, :unretire

    # Authenticated documentation endpoints (delete requires auth)
    delete "/packages/:name/releases/:version/docs", DocsController, :delete

    # Authenticated ownership endpoints (write operations)
    put "/packages/:name/owners/:email", OwnerController, :add
    delete "/packages/:name/owners/:email", OwnerController, :remove

    # API Keys endpoints (write operations)
    post "/keys", KeyController, :create
    delete "/keys/:name", KeyController, :delete

    # Admin endpoints
    post "/packages/search/reindex", SearchController, :reindex
  end

  # Public user lookup - MUST come after /users/me route to avoid matching "me" as username
  scope "/api", HexHubWeb.API do
    pipe_through :api

    get "/users/:username_or_email", UserController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hex_hub, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HexHubWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
