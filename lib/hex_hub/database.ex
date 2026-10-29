defmodule HexHub.Database do
  @moduledoc """
  Metadata persistence with selectable Mnesia and PostgreSQL backends.

  Records and transaction results retain their existing tuple format so that
  package, authentication, cache, and backup operations use the same contract.
  """

  alias HexHub.Database.{Postgres, Repo, Schema}

  def backend, do: Application.get_env(:hex_hub, :database_backend, :mnesia)

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  def start_link(_opts) do
    children = if backend() == :postgresql, do: [Repo], else: []

    with {:ok, pid} <-
           Supervisor.start_link(children,
             strategy: :one_for_one,
             name: HexHub.Database.Supervisor
           ) do
      :ok = initialize()
      {:ok, pid}
    end
  end

  defp initialize do
    case backend() do
      :mnesia ->
        configure_mnesia_dir()
        :ok = HexHub.Clustering.init_clustering()
        :ok = HexHub.Mnesia.init()
        :ok = HexHub.Mnesia.migrate_package_source_field()

      :postgresql ->
        :ok = Postgres.init()
    end

    :ok = HexHub.Audit.init()
    :ok = HexHub.PackageSearch.init_tables()
    :ok = HexHub.UpstreamConfig.init_default_config()
    :ok = HexHub.PublishConfig.init_default_config()
    :ok = HexHub.StorageConfig.init_default_config()
    HexHub.Users.ensure_anonymous_user()
    :ok
  end

  def reset_tables do
    Enum.each(Schema.tables() ++ [:package_search_index, :search_cache], &clear_table/1)
    :ok
  end

  def tables, do: Schema.tables()

  for {operation, arity} <- [
        transaction: 1,
        sync_transaction: 1,
        abort: 1,
        read: 1,
        read: 2,
        write: 1,
        delete: 1,
        delete_object: 1,
        dirty_read: 2,
        dirty_write: 1,
        dirty_delete: 2,
        match_object: 1,
        dirty_match_object: 1,
        dirty_match_object: 2,
        foldl: 3,
        select: 2,
        index_read: 3,
        table_info: 2,
        system_info: 1,
        clear_table: 1,
        create_table: 2,
        wait_for_tables: 2
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(operation)(unquote_splicing(args)) do
      adapter = if backend() == :postgresql, do: Postgres, else: :mnesia
      apply(adapter, unquote(operation), [unquote_splicing(args)])
    end
  end

  defp configure_mnesia_dir do
    case Application.get_env(:hex_hub, :mnesia_dir) do
      nil ->
        :ok

      dir ->
        File.mkdir_p!(dir)
        Application.put_env(:mnesia, :dir, String.to_charlist(dir))
    end
  end
end
