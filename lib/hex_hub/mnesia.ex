defmodule HexHub.Mnesia do
  @moduledoc """
  Mnesia configuration and initialization module.
  """

  @tables [
    :users,
    :repositories,
    :packages,
    :package_releases,
    :package_owners,
    :api_keys,
    :package_downloads,
    :rate_limit,
    :audit_logs,
    :upstream_configs,
    :publish_configs,
    :blocked_addresses,
    :retired_releases,
    :system_metadata,
    :backups
  ]

  @doc """
  Initialize Mnesia tables on application start.
  """
  def init() do
    ensure_mnesia_running()
    create_tables()
    create_indices()
    migrate_to_disc_copies()
    wait_for_tables()
  end

  # Wait for all tables to be fully loaded from disc
  # This is crucial for disc_copies tables to ensure data is available
  defp wait_for_tables do
    case :mnesia.wait_for_tables(@tables, 30_000) do
      :ok ->
        :ok

      {:timeout, remaining} ->
        IO.warn("Timeout waiting for Mnesia tables: #{inspect(remaining)}")
        :ok

      {:error, reason} ->
        IO.warn("Error waiting for Mnesia tables: #{inspect(reason)}")
        :ok
    end
  end

  defp ensure_mnesia_running do
    case :mnesia.system_info(:is_running) do
      :no ->
        # Ensure schema exists for current node
        ensure_schema()
        :mnesia.start()

      _ ->
        # Already running, ensure current node is in schema
        ensure_node_in_schema()
    end
  end

  defp ensure_schema do
    case :mnesia.create_schema([node()]) do
      :ok ->
        :ok

      {:error, {_, {:already_exists, _}}} ->
        # Schema exists, check if current node is included
        :ok

      {:error, reason} ->
        IO.warn("Failed to create Mnesia schema: #{inspect(reason)}")
        :ok
    end
  end

  defp ensure_node_in_schema do
    # Check if current node has disc copies capability
    # by checking if it's in the schema nodes
    case :mnesia.table_info(:schema, :disc_copies) do
      nodes when is_list(nodes) ->
        if node() in nodes do
          :ok
        else
          # Node not in schema, try to add it
          add_node_to_schema()
        end

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp add_node_to_schema do
    # Try to add current node to schema for disc_copies support
    case :mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
      {:atomic, :ok} ->
        IO.puts("Added node #{node()} to Mnesia schema with disc_copies")
        :ok

      {:aborted, {:already_exists, :schema, _, :disc_copies}} ->
        :ok

      {:aborted, reason} ->
        IO.warn("Could not add node to schema: #{inspect(reason)}")
        :ok
    end
  end

  defp create_tables() do
    # Determine storage type based on node configuration
    # disc_copies requires a proper node name (not nonode@nohost)
    # Fall back to ram_copies for development without node name
    storage_type = get_storage_type()

    tables = [
      {:users,
       [
         attributes: [
           :username,
           :email,
           :password_hash,
           :totp_secret,
           :totp_enabled,
           :recovery_codes,
           :service_account,
           :deactivated_at,
           :inserted_at,
           :updated_at
         ],
         type: :set,
         index: [:email, :service_account]
       ] ++ storage_opt(storage_type)},
      {:repositories,
       [
         attributes: [:name, :public, :active, :billing_active, :inserted_at, :updated_at],
         type: :set
       ] ++ storage_opt(storage_type)},
      {:packages,
       [
         attributes: [
           :name,
           :repository_name,
           :meta,
           :private,
           :downloads,
           :inserted_at,
           :updated_at,
           :html_url,
           :docs_html_url,
           :source
         ],
         type: :set
       ] ++ storage_opt(storage_type)},
      {:package_releases,
       [
         attributes: [
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
         ],
         type: :bag
       ] ++ storage_opt(storage_type)},
      {:package_owners,
       [
         attributes: [:package_name, :username, :level, :inserted_at],
         type: :bag
       ] ++ storage_opt(storage_type)},
      {:api_keys,
       [
         attributes: [
           :name,
           :username,
           :secret_hash,
           :permissions,
           :revoked_at,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ] ++ storage_opt(storage_type)},
      {:package_downloads,
       [
         attributes: [:package_name, :version, :day_count, :week_count, :all_count],
         type: :set
       ] ++ storage_opt(storage_type)},
      # Rate limit is always ephemeral - no need to persist across restarts
      {:rate_limit,
       [
         attributes: [:key, :type, :identifier, :count, :window_start, :updated_at],
         type: :set,
         ram_copies: [node()]
       ]},
      {:audit_logs,
       [
         attributes: [
           :id,
           :timestamp,
           :user_id,
           :action,
           :resource_type,
           :resource_id,
           :details,
           :ip_address,
           :user_agent
         ],
         type: :ordered_set,
         index: [:user_id, :resource_type, :timestamp]
       ] ++ storage_opt(storage_type)},
      {:upstream_configs,
       [
         attributes: [
           :id,
           :enabled,
           :api_url,
           :repo_url,
           :api_key,
           :timeout,
           :retry_attempts,
           :retry_delay,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ] ++ storage_opt(storage_type)},
      {:publish_configs,
       [
         attributes: [
           :id,
           :enabled,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ] ++ storage_opt(storage_type)},
      {:blocked_addresses,
       [
         attributes: [:ip_address, :type, :reason, :blocked_at, :blocked_until, :created_by],
         type: :set,
         index: [:type, :blocked_until]
       ] ++ storage_opt(storage_type)},
      {:retired_releases,
       [
         attributes: [:key, :package_name, :version, :reason, :message, :retired_at, :retired_by],
         type: :set,
         index: [:package_name]
       ] ++ storage_opt(storage_type)},
      {:system_metadata,
       [
         attributes: [:key, :value],
         type: :set
       ] ++ storage_opt(storage_type)},
      {:backups,
       [
         attributes: [
           :id,
           :filename,
           :file_path,
           :size_bytes,
           :user_count,
           :package_count,
           :release_count,
           :created_by,
           :status,
           :error_message,
           :created_at,
           :completed_at,
           :expires_at
         ],
         type: :set,
         index: [:created_at, :expires_at]
       ] ++ storage_opt(storage_type)}
    ]

    Enum.each(tables, fn {table_name, opts} ->
      create_table_with_fallback(table_name, opts, storage_type)
    end)
  end

  # Try to create table, falling back to ram_copies if disc_copies fails
  defp create_table_with_fallback(table_name, opts, :disc_copies) do
    case :mnesia.create_table(table_name, opts) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, ^table_name}} ->
        :ok

      {:aborted, {:bad_type, ^table_name, :disc_copies, _node}} ->
        # disc_copies failed (schema issue), fall back to ram_copies
        IO.puts("Falling back to ram_copies for table #{table_name}")
        fallback_opts = Keyword.delete(opts, :disc_copies) ++ [ram_copies: [node()]]
        create_table_with_fallback(table_name, fallback_opts, :ram_copies)

      {:aborted, reason} ->
        IO.warn("Failed to create table #{table_name}: #{inspect(reason)}")
    end
  end

  defp create_table_with_fallback(table_name, opts, :ram_copies) do
    case :mnesia.create_table(table_name, opts) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^table_name}} -> :ok
      {:aborted, reason} -> IO.warn("Failed to create table #{table_name}: #{inspect(reason)}")
    end
  end

  # Determine storage type based on node configuration
  # disc_copies requires a proper distributed node name
  defp get_storage_type do
    case node() do
      :nonode@nohost ->
        # Running without a node name, can't use disc_copies
        # This is typical for development with `mix phx.server`
        :ram_copies

      _ ->
        # Running with a node name, try disc_copies for persistence
        # Will fall back to ram_copies if schema doesn't support it
        :disc_copies
    end
  end

  # Generate storage option keyword list based on storage type
  defp storage_opt(:disc_copies), do: [disc_copies: [node()]]
  defp storage_opt(:ram_copies), do: [ram_copies: [node()]]

  defp create_indices() do
    # Additional indices for common queries
    indices = [
      {:packages, :inserted_at},
      {:packages, :source},
      {:package_releases, :inserted_at},
      {:users, :email},
      {:audit_logs, :user_id},
      {:audit_logs, :resource_type},
      {:audit_logs, :timestamp}
    ]

    Enum.each(indices, fn {table, attribute} ->
      case :mnesia.add_table_index(table, attribute) do
        {:atomic, :ok} ->
          :ok

        {:aborted, {:already_exists, _, _}} ->
          :ok

        {:aborted, reason} ->
          IO.warn("Failed to add index on #{table}.#{attribute}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Migrate existing packages to add the source field.
  Existing packages default to :local source.

  Note: This migration only applies to packages created before the source field
  was added. New packages already have the source field.
  """
  def migrate_package_source_field do
    # Check if migration is needed by looking at table attributes
    # If the table already has the source field in its schema, no migration needed
    case :mnesia.table_info(:packages, :attributes) do
      attributes when is_list(attributes) ->
        if :source in attributes do
          # Table already has source field, no migration needed
          :ok
        else
          do_migrate_package_source_field()
        end

      _ ->
        # Table info not available, skip migration
        :ok
    end
  rescue
    _ ->
      # Mnesia not ready or table doesn't exist, skip migration
      :ok
  end

  defp do_migrate_package_source_field do
    case :mnesia.transaction(fn ->
           # Use foldl to iterate over all packages and check their size
           :mnesia.foldl(
             fn pkg, acc ->
               if tuple_size(pkg) == 10 do
                 # Old record format (10 fields), add source: :local
                 new_pkg = Tuple.insert_at(pkg, tuple_size(pkg), :local)
                 :mnesia.delete_object(pkg)
                 :mnesia.write(new_pkg)
                 acc + 1
               else
                 acc
               end
             end,
             0,
             :packages
           )
         end) do
      {:atomic, count} when count > 0 ->
        IO.puts("Migrated #{count} packages to include source field")
        :ok

      {:atomic, 0} ->
        :ok

      {:aborted, reason} ->
        IO.warn("Failed to migrate package source field: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Reset all tables (useful for development/testing).
  """
  def reset_tables() do
    Enum.each(@tables, fn table ->
      :mnesia.delete_table(table)
    end)

    :mnesia.stop()
    :mnesia.delete_schema([node()])
    init()
  end

  @doc """
  Get all table names.
  """
  def tables(), do: @tables

  @doc """
  Migrate existing ram_copies tables to disc_copies for data persistence.
  This is needed for deployments that were created before disc_copies was enabled.
  Only runs when the node has a proper distributed name (not nonode@nohost).
  """
  def migrate_to_disc_copies do
    # Only migrate if we have a proper node name that supports disc_copies
    case node() do
      :nonode@nohost ->
        # Can't use disc_copies without a node name, skip migration
        :ok

      _ ->
        do_migrate_to_disc_copies()
    end
  end

  defp do_migrate_to_disc_copies do
    # Tables that should use disc_copies for persistence
    persistent_tables = [
      :users,
      :repositories,
      :packages,
      :package_releases,
      :package_owners,
      :api_keys,
      :package_downloads,
      :audit_logs,
      :upstream_configs,
      :publish_configs,
      :blocked_addresses,
      :retired_releases,
      :system_metadata,
      :backups
    ]

    Enum.each(persistent_tables, fn table ->
      migrate_table_to_disc_copies(table)
    end)
  end

  defp migrate_table_to_disc_copies(table) do
    node = node()

    try do
      # Check current storage type for this table
      case :mnesia.table_info(table, :storage_type) do
        :ram_copies ->
          # Table exists as ram_copies, convert to disc_copies
          case :mnesia.change_table_copy_type(table, node, :disc_copies) do
            {:atomic, :ok} ->
              IO.puts("Migrated table #{table} from ram_copies to disc_copies")
              :ok

            {:aborted, {:already_exists, ^table, ^node, :disc_copies}} ->
              :ok

            {:aborted, reason} ->
              IO.warn("Failed to migrate table #{table} to disc_copies: #{inspect(reason)}")
              {:error, reason}
          end

        :disc_copies ->
          # Already disc_copies, nothing to do
          :ok

        :disc_only_copies ->
          # Already on disc, nothing to do
          :ok

        other ->
          IO.warn("Table #{table} has unexpected storage type: #{inspect(other)}")
          :ok
      end
    rescue
      e ->
        IO.warn("Error checking table #{table}: #{inspect(e)}")
        :ok
    end
  end

  @doc """
  Debug function to inspect package sources in the database.
  Returns a summary of packages by source type.
  """
  def debug_package_sources do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn pkg, acc ->
               size = tuple_size(pkg)
               source = if size == 11, do: elem(pkg, 10), else: :unknown
               name = if size >= 2, do: elem(pkg, 1), else: :unknown

               Map.update(acc, source, [{name, size}], fn list -> [{name, size} | list] end)
             end,
             %{},
             :packages
           )
         end) do
      {:atomic, summary} ->
        %{
          local: length(Map.get(summary, :local, [])),
          cached: length(Map.get(summary, :cached, [])),
          unknown: length(Map.get(summary, :unknown, [])),
          details: summary
        }

      {:aborted, reason} ->
        {:error, reason}
    end
  end
end
