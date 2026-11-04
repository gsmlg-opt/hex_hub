defmodule HexHub.Mnesia do
  @moduledoc """
  Mnesia configuration and initialization module.
  """

  @tables HexHub.Database.Schema.tables()

  @doc """
  Initialize Mnesia tables on application start.
  """
  def init() do
    prepare_directory()
    :ok = HexHub.Clustering.init_clustering()
    :ok = ensure_mnesia_running()
    create_tables()
    wait_for_tables()
    create_indices()
    migrate_to_disc_copies()
    :ok = migrate_api_keys_add_secret_and_last_accessed()
    wait_for_tables()
  end

  defp prepare_directory do
    directory =
      (Application.get_env(:hex_hub, :mnesia_dir) || :mnesia.system_info(:directory))
      |> IO.chardata_to_string()
      |> Path.expand()

    if :mnesia.system_info(:is_running) != :no do
      running_directory = :mnesia.system_info(:directory) |> to_string() |> Path.expand()

      if directory != running_directory do
        raise "Mnesia is already running in #{inspect(running_directory)}, but MNESIA_DIR is " <>
                "#{inspect(directory)}. Refusing to switch directories; verify the existing " <>
                "data and restart with the intended directory."
      end
    end

    probe =
      Path.join(
        directory,
        ".hex_hub_write_check_#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(probe, "", [:exclusive]),
         :ok <- File.rm(probe) do
      Application.put_env(:mnesia, :dir, String.to_charlist(directory))
    else
      {:error, reason} ->
        raise "Mnesia directory #{inspect(directory)} is not writable: " <>
                "#{:file.format_error(reason)}. Ensure MNESIA_DIR and its files are writable " <>
                "by the application user; check bind-mount ownership and permissions."
    end
  end

  # Wait for all tables to be fully loaded from disc
  # This is crucial for disc_copies tables to ensure data is available
  defp wait_for_tables do
    case :mnesia.wait_for_tables(@tables, 30_000) do
      :ok ->
        :ok

      {:timeout, remaining} ->
        raise "Timeout waiting for Mnesia tables: #{inspect(remaining)}"

      {:error, reason} ->
        raise "Error waiting for Mnesia tables: #{inspect(reason)}"
    end
  end

  defp ensure_mnesia_running do
    case :mnesia.system_info(:is_running) do
      :no ->
        # Ensure schema exists for current node
        ensure_schema()

        case :mnesia.start() do
          :ok -> :ok
          {:error, reason} -> raise "Failed to start Mnesia: #{inspect(reason)}"
        end

      :yes ->
        # Already running, ensure current node is in schema
        ensure_node_in_schema()

      status ->
        raise "Cannot initialize Mnesia while it is #{inspect(status)}"
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
        raise "Failed to create Mnesia schema: #{inspect(reason)}"
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
    end
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
        raise "Could not persist the Mnesia schema: #{inspect(reason)}"
    end
  end

  defp create_tables() do
    Enum.each(HexHub.Database.Schema.definitions(), fn {table_name, opts} ->
      opts =
        if Keyword.has_key?(opts, :ram_copies),
          do: opts,
          else: opts ++ [disc_copies: [node()]]

      create_table(table_name, opts)
    end)
  end

  defp create_table(table_name, opts) do
    case :mnesia.create_table(table_name, opts) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, ^table_name}} ->
        :ok

      {:aborted, reason} ->
        raise "Failed to create Mnesia table #{table_name}: #{inspect(reason)}"
    end
  end

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
  Migrate api_keys table to add :secret and :last_accessed_at fields.

  Old schema (8 elements): {:api_keys, name, username, secret_hash, permissions, revoked_at, inserted_at, updated_at}
  New schema (10 elements): {:api_keys, name, username, secret, secret_hash, permissions, revoked_at, last_accessed_at, inserted_at, updated_at}
  """
  def migrate_api_keys_add_secret_and_last_accessed do
    current_attrs = :mnesia.table_info(:api_keys, :attributes)

    if :secret not in current_attrs or :last_accessed_at not in current_attrs do
      new_attributes = [
        :name,
        :username,
        :secret,
        :secret_hash,
        :permissions,
        :revoked_at,
        :last_accessed_at,
        :inserted_at,
        :updated_at
      ]

      transform_fn = fn
        {:api_keys, name, username, secret_hash, permissions, revoked_at, inserted_at, updated_at} ->
          {:api_keys, name, username, nil, secret_hash, permissions, revoked_at, nil, inserted_at,
           updated_at}

        record when tuple_size(record) == 10 ->
          # Already migrated
          record
      end

      case :mnesia.transform_table(:api_keys, transform_fn, new_attributes) do
        {:atomic, :ok} ->
          IO.puts("Migrated api_keys table: added :secret and :last_accessed_at fields")
          :ok

        {:aborted, {:already_exists, :api_keys}} ->
          :ok

        {:aborted, reason} ->
          IO.warn("Failed to migrate api_keys table: #{inspect(reason)}")
          {:error, reason}
      end
    else
      :ok
    end
  rescue
    _ -> :ok
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
  Fails startup if a persistent table cannot be stored on disk.
  """
  def migrate_to_disc_copies do
    Enum.each(@tables -- [:rate_limit], fn table ->
      migrate_table_to_disc_copies(table)
    end)
  end

  defp migrate_table_to_disc_copies(table) do
    node = node()

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
            raise "Failed to persist Mnesia table #{table}: #{inspect(reason)}"
        end

      :disc_copies ->
        # Already disc_copies, nothing to do
        :ok

      :disc_only_copies ->
        # Already on disc, nothing to do
        :ok

      other ->
        raise "Mnesia table #{table} has unexpected storage type: #{inspect(other)}"
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
