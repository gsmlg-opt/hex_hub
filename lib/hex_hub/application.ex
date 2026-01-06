defmodule HexHub.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Record application start time for uptime calculation
    :persistent_term.put(:hex_hub_start_time, System.system_time(:second))

    # Attach telemetry log handlers
    attach_telemetry_handlers()

    # Initialize clustering if enabled
    HexHub.Clustering.init_clustering()

    # Configure Mnesia directory before starting
    configure_mnesia_dir()

    # Start Mnesia only if not already started and clustering is not handling it
    unless Process.whereis(:mnesia_sup) do
      :mnesia.start()
    end

    # Create Mnesia tables if they don't exist
    HexHub.Mnesia.init()
    HexHub.Audit.init()

    # Migrate existing packages to include source field (if needed)
    HexHub.Mnesia.migrate_package_source_field()

    # Initialize default upstream configuration if needed
    HexHub.UpstreamConfig.init_default_config()

    # Initialize default publish configuration if needed
    HexHub.PublishConfig.init_default_config()

    # Ensure anonymous user exists for anonymous publishing feature
    HexHub.Users.ensure_anonymous_user()

    children = [
      # Start the Telemetry supervisor
      HexHubWeb.Telemetry,
      # Start the admin telemetry supervisor
      HexHubAdminWeb.Telemetry,
      # Start the custom telemetry poller
      {HexHub.Telemetry, []},
      # Start the PubSub system
      {Phoenix.PubSub, name: HexHub.PubSub},
      # Start the Endpoint (http/https)
      HexHubWeb.Endpoint,
      # Start the Admin Endpoint (http/https)
      HexHubAdminWeb.Endpoint,
      # Start the backup cleanup GenServer
      HexHub.Backup.Cleanup
    ]

    # Add MCP server only if enabled
    children =
      if Application.get_env(:hex_hub, :mcp, [])[:enabled] do
        children ++
          [
            %{
              id: HexHub.MCP,
              start: {HexHub.MCP, :start, [:normal, []]},
              type: :supervisor,
              restart: :permanent,
              shutdown: 5000
            }
          ]
      else
        children
      end

    # Add clustering supervisor only if clustering is enabled
    children =
      case Application.get_env(:libcluster, :topologies, []) do
        [] -> children
        topologies -> children ++ [{Cluster.Supervisor, topologies}]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HexHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HexHubWeb.Endpoint.config_change(changed, removed)
    HexHubAdminWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @doc """
  Returns the application start time in seconds since epoch.
  """
  def start_time do
    :persistent_term.get(:hex_hub_start_time, 0)
  end

  # Attaches telemetry handlers for logging based on configuration.
  # Handlers are attached for all log categories defined in HexHub.Telemetry.
  defp attach_telemetry_handlers do
    config = Application.get_env(:hex_hub, :telemetry_logging, [])

    # Define all log event patterns to attach
    log_events = [
      [:hex_hub, :log, :api],
      [:hex_hub, :log, :upstream],
      [:hex_hub, :log, :storage],
      [:hex_hub, :log, :auth],
      [:hex_hub, :log, :package],
      [:hex_hub, :log, :mcp],
      [:hex_hub, :log, :cluster],
      [:hex_hub, :log, :config],
      [:hex_hub, :log, :user],
      [:hex_hub, :log, :general]
    ]

    # Attach console handler if enabled
    console_config = Keyword.get(config, :console, [])

    if Keyword.get(console_config, :enabled, true) do
      attach_handler(
        "hex_hub_console_log",
        log_events,
        HexHub.Telemetry.LogHandler,
        console_config
      )
    end

    # Attach file handler if enabled
    file_config = Keyword.get(config, :file, [])

    if Keyword.get(file_config, :enabled, false) and Keyword.get(file_config, :path) do
      attach_handler("hex_hub_file_log", log_events, HexHub.Telemetry.FileHandler, file_config)
    end
  end

  # Attaches a telemetry handler, detaching any existing handler with the same ID first
  # to prevent duplicate handler errors on restart.
  defp attach_handler(handler_id, events, handler_module, config) do
    # Detach existing handler if present (prevents duplicate handler errors)
    :telemetry.detach(handler_id)

    :telemetry.attach_many(
      handler_id,
      events,
      &handler_module.handle_event/4,
      config
    )
  end

  # Configures the Mnesia directory based on application configuration.
  # Must be called before Mnesia is started.
  defp configure_mnesia_dir do
    case Application.get_env(:hex_hub, :mnesia_dir) do
      nil ->
        :ok

      dir when is_binary(dir) ->
        # Ensure the directory exists
        File.mkdir_p!(dir)
        # Set the Mnesia directory
        Application.put_env(:mnesia, :dir, String.to_charlist(dir))
    end
  end
end
