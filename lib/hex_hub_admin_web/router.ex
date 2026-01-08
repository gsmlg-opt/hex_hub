defmodule HexHubAdminWeb.Router do
  use HexHubAdminWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HexHubAdminWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin_auth do
    plug HexHubAdminWeb.Plugs.AdminAuth
  end

  pipeline :browser_api do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Admin dashboard routes (protected by basic auth)
  scope "/", HexHubAdminWeb do
    pipe_through [:browser, :admin_auth]

    get "/", AdminController, :dashboard
    get "/repositories", RepositoryController, :index
    get "/repositories/new", RepositoryController, :new
    post "/repositories", RepositoryController, :create
    get "/repositories/:name/edit", RepositoryController, :edit
    put "/repositories/:name", RepositoryController, :update
    delete "/repositories/:name", RepositoryController, :delete

    get "/packages", PackageController, :index
    get "/packages/new", PackageController, :new
    get "/packages/search", PackageController, :search
    post "/packages", PackageController, :create
    get "/packages/:name", PackageController, :show
    get "/packages/:name/edit", PackageController, :edit
    put "/packages/:name", PackageController, :update
    delete "/packages/:name", PackageController, :delete

    get "/users", UserController, :index
    get "/users/new", UserController, :new
    post "/users", UserController, :create
    get "/users/:username", UserController, :show
    get "/users/:username/edit", UserController, :edit
    put "/users/:username", UserController, :update
    delete "/users/:username", UserController, :delete

    get "/upstream", UpstreamController, :index
    get "/upstream/edit", UpstreamController, :edit
    put "/upstream", UpstreamController, :update
    post "/upstream/test-connection", UpstreamController, :test_connection

    get "/storage", StorageController, :index
    get "/storage/edit", StorageController, :edit
    put "/storage", StorageController, :update
    post "/storage/test-connection", StorageController, :test_connection

    # Publish configuration
    get "/publish-config", PublishConfigController, :index
    put "/publish-config", PublishConfigController, :update

    # Local and cached package management
    resources "/local-packages", LocalPackageController, only: [:index, :show]

    resources "/cached-packages", CachedPackageController, only: [:index, :show, :delete]
    delete "/cached-packages", CachedPackageController, :clear_all

    # Backup management
    get "/backups", BackupController, :index
    get "/backups/new", BackupController, :new
    get "/backups/restore", BackupController, :restore_form
    post "/backups", BackupController, :create
    post "/backups/restore", BackupController, :restore
    get "/backups/:id", BackupController, :show
    get "/backups/:id/download", BackupController, :download
    delete "/backups/:id", BackupController, :delete
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:hex_hub, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HexHubAdminWeb.Telemetry
    end
  end
end
