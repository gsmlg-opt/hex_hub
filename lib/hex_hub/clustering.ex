defmodule HexHub.Clustering do
  @moduledoc """
  Mnesia clustering configuration and management for high availability.

  This module provides functionality to:
  - Configure Mnesia clustering between nodes
  - Handle node discovery and joining
  - Manage table replication across nodes
  - Provide failover and recovery capabilities
  """

  alias HexHub.Telemetry

  @doc """
  Initialize Mnesia clustering based on configuration.
  """
  def init_clustering do
    case {HexHub.Database.backend(), Application.get_env(:hex_hub, :clustering, %{})} do
      {:mnesia, %{enabled: true} = config} ->
        configure_clustering(config)

      _ ->
        :ok
    end
  end

  @doc """
  Configure Mnesia clustering with the given configuration.
  """
  def configure_clustering(config) do
    Telemetry.log(:info, :cluster, "Configuring Mnesia clustering")

    # Set Mnesia directory via application environment
    mnesia_dir = Application.get_env(:hex_hub, :mnesia_dir, "./mnesia/#{node()}")
    Application.put_env(:mnesia, :dir, to_charlist(mnesia_dir))

    # Set schema location
    :mnesia.set_master_nodes([node()])

    # Configure table replication
    configure_table_replication(config)

    # Start Mnesia
    case :mnesia.start() do
      :ok ->
        Telemetry.log(:info, :cluster, "Mnesia started successfully")
        :ok

      {:error, {:already_started, _}} ->
        Telemetry.log(:info, :cluster, "Mnesia already started")
        :ok

      error ->
        Telemetry.log(:error, :cluster, "Failed to start Mnesia", %{error: inspect(error)})
        error
    end
  end

  @doc """
  Configure table replication across cluster nodes.
  """
  def configure_table_replication(config) do
    nodes = get_cluster_nodes(config)

    if Enum.empty?(nodes) do
      Telemetry.log(:info, :cluster, "Running in single-node mode")
      :ok
    else
      Telemetry.log(:info, :cluster, "Configuring replication across nodes", %{nodes: nodes})

      # Ensure schema is created on all nodes
      :mnesia.change_table_copy_type(:schema, node(), :disc_copies)

      Enum.each(nodes, fn node ->
        if node != node() do
          :mnesia.change_table_copy_type(:schema, node, :disc_copies)
        end
      end)

      # Configure replication for each table
      tables = [:packages, :package_releases, :package_owners, :users, :keys, :audit_logs]

      Enum.each(tables, fn table ->
        configure_table_replication_for(table, nodes, config)
      end)

      :ok
    end
  end

  defp configure_table_replication_for(table, nodes, config) do
    replication_factor = Map.get(config, :replication_factor, 2)

    case :mnesia.create_table(table,
           attributes: get_table_attributes(table),
           type: get_table_type(table),
           disc_copies: Enum.take(nodes ++ [node()], replication_factor)
         ) do
      {:atomic, :ok} ->
        Telemetry.log(:info, :cluster, "Created table with replication", %{table: table})

      {:aborted, {:already_exists, ^table}} ->
        Telemetry.log(:info, :cluster, "Table already exists, updating replication", %{
          table: table
        })

        update_table_replication(table, nodes, replication_factor)

      error ->
        Telemetry.log(:error, :cluster, "Failed to create table", %{
          table: table,
          error: inspect(error)
        })
    end
  end

  defp update_table_replication(table, nodes, replication_factor) do
    current_copies = :mnesia.table_info(table, :disc_copies)
    target_nodes = Enum.take(nodes ++ [node()], replication_factor)

    # Add missing copies
    Enum.each(target_nodes -- current_copies, fn node ->
      Telemetry.log(:info, :cluster, "Adding table replica", %{table: table, node: node})
      :mnesia.add_table_copy(table, node, :disc_copies)
    end)

    # Remove extra copies
    Enum.each(current_copies -- target_nodes, fn node ->
      Telemetry.log(:info, :cluster, "Removing table replica", %{table: table, node: node})
      :mnesia.del_table_copy(table, node)
    end)
  end

  defp get_table_attributes(:packages),
    do: [
      :name,
      :repository_name,
      :meta,
      :private,
      :downloads,
      :inserted_at,
      :updated_at,
      :html_url,
      :docs_html_url
    ]

  defp get_table_attributes(:package_releases),
    do: [
      :package_name,
      :version,
      :has_docs,
      :meta,
      :requirements,
      :retired,
      :downloads,
      :inserted_at,
      :updated_at,
      :url,
      :package_url,
      :html_url,
      :docs_html_url
    ]

  defp get_table_attributes(:package_owners), do: [:package_name, :user_id, :level, :inserted_at]

  defp get_table_attributes(:users),
    do: [:id, :username, :email, :full_name, :inserted_at, :updated_at]

  defp get_table_attributes(:keys),
    do: [:id, :user_id, :name, :permissions, :last_used_at, :inserted_at]

  defp get_table_attributes(:audit_logs),
    do: [:id, :action, :entity_type, :entity_id, :metadata, :user_id, :timestamp]

  defp get_table_attributes(_), do: []

  defp get_table_type(:packages), do: :set
  defp get_table_type(:package_releases), do: :bag
  defp get_table_type(:package_owners), do: :bag
  defp get_table_type(:users), do: :set
  defp get_table_type(:keys), do: :set
  defp get_table_type(:audit_logs), do: :set

  @doc """
  Get cluster nodes from configuration.
  """
  def get_cluster_nodes(config) do
    case config do
      %{nodes: nodes} when is_list(nodes) ->
        Enum.map(nodes, &String.to_atom/1)

      %{discovery: %{type: "dns", hostname: hostname}} ->
        discover_nodes_via_dns(hostname)

      %{discovery: %{type: "epmd"}} ->
        discover_nodes_via_epmd()

      _ ->
        []
    end
  end

  @doc """
  Discover cluster nodes via DNS SRV records.
  """
  def discover_nodes_via_dns(hostname) do
    # DNS SRV lookups require a different approach
    # For now, we'll return empty list as this is a placeholder implementation
    # In production, use a proper DNS library like inet_res with correct record types
    _ = hostname
    []
  end

  @doc """
  Discover cluster nodes via EPMD.
  """
  def discover_nodes_via_epmd do
    case :net_adm.names() do
      {:ok, names} ->
        Enum.map(names, fn {name, _port} ->
          String.to_atom("#{name}@#{node_host()}")
        end)

      _ ->
        []
    end
  end

  @doc """
  Join an existing cluster.
  """
  def join_cluster(node) when is_binary(node), do: join_cluster(String.to_atom(node))

  def join_cluster(node) do
    if HexHub.Database.backend() == :postgresql do
      {:error, :requires_mnesia}
    else
      do_join_cluster(node)
    end
  end

  defp do_join_cluster(node) do
    Telemetry.log(:info, :cluster, "Attempting to join cluster node", %{node: node})

    case :net_adm.ping(node) do
      :pong ->
        Telemetry.log(:info, :cluster, "Successfully connected to node", %{node: node})

        # Stop Mnesia to change configuration
        :mnesia.stop()

        # Change schema to include new node
        :mnesia.change_config(:extra_db_nodes, [node])

        # Start Mnesia
        :mnesia.start()

        # Wait for tables to load
        wait_for_tables()

        Telemetry.log(:info, :cluster, "Successfully joined cluster")
        {:ok, :joined}

      :pang ->
        Telemetry.log(:error, :cluster, "Failed to connect to node", %{node: node})
        {:error, :connection_failed}
    end
  end

  @doc """
  Leave the cluster.
  """
  def leave_cluster do
    if HexHub.Database.backend() == :postgresql do
      {:error, :requires_mnesia}
    else
      do_leave_cluster()
    end
  end

  defp do_leave_cluster do
    Telemetry.log(:info, :cluster, "Leaving cluster")

    # Stop Mnesia
    :mnesia.stop()

    # Reset schema
    :mnesia.delete_schema([node()])

    # Start fresh
    :mnesia.start()

    Telemetry.log(:info, :cluster, "Left cluster successfully")
    {:ok, :left}
  end

  @doc """
  Wait for all tables to be loaded.
  """
  def wait_for_tables do
    tables = [:packages, :package_releases, :package_owners, :users, :keys, :audit_logs]

    case :mnesia.wait_for_tables(tables, 30_000) do
      :ok ->
        Telemetry.log(:info, :cluster, "All tables loaded successfully")
        :ok

      {:timeout, failed_tables} ->
        Telemetry.log(:error, :cluster, "Timeout waiting for tables", %{
          failed_tables: failed_tables
        })

        {:error, :timeout}

      error ->
        Telemetry.log(:error, :cluster, "Error waiting for tables", %{error: inspect(error)})
        error
    end
  end

  @doc """
  Get cluster status information.
  """
  def get_cluster_status do
    if HexHub.Database.backend() == :postgresql do
      %{
        node: node(),
        backend: :postgresql,
        running: HexHub.Database.system_info(:is_running),
        tables:
          Enum.map(HexHub.Database.tables(), fn table ->
            %{name: table, size: HexHub.Database.table_info(table, :size)}
          end),
        connected_nodes: Node.list()
      }
    else
      mnesia_cluster_status()
    end
  end

  defp mnesia_cluster_status do
    %{
      node: node(),
      running: :mnesia.system_info(:is_running),
      tables:
        Enum.map(
          [:packages, :package_releases, :package_owners, :users, :keys, :audit_logs],
          fn table ->
            %{
              name: table,
              size: :mnesia.table_info(table, :size),
              memory: :mnesia.table_info(table, :memory),
              disc_copies: :mnesia.table_info(table, :disc_copies),
              ram_copies: :mnesia.table_info(table, :ram_copies)
            }
          end
        ),
      connected_nodes: Node.list()
    }
  end

  defp node_host do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end
end
