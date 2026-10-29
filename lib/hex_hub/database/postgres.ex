defmodule HexHub.Database.Postgres do
  @moduledoc """
  PostgreSQL record storage for the existing metadata contract.

  Each logical table has indexed record keys and binary Erlang records, preserving
  maps, atoms, timestamps, and binary registry responses without JSON conversion.
  Set tables replace records by key; bag tables retain distinct objects per key.
  Pattern queries use Erlang match specifications after loading candidate records.
  """

  alias Ecto.Adapters.SQL
  alias HexHub.Database.{Repo, Schema}

  @search_tables [
    package_search_index: [
      attributes: [:term, :field, :package_name, :position, :score],
      type: :bag
    ],
    search_cache: [attributes: [:query, :results, :timestamp], type: :set]
  ]
  @retries 20

  def init do
    {:ok, :ok} =
      Repo.transact(fn ->
        # Serialize schema creation when multiple nodes start against a new database.
        SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1)", [0x486578487562])

        Enum.each(Schema.definitions() ++ @search_tables, fn {table, opts} ->
          {:atomic, :ok} = create_table(table, opts)
        end)

        {:ok, :ok}
      end)

    :ok
  end

  def create_table(table, _opts) do
    # Names are checked against the application schema before SQL interpolation.
    name = table_name(table)

    SQL.query!(Repo, """
    CREATE TABLE IF NOT EXISTS #{name} (
      record_key bytea NOT NULL,
      object_hash bytea NOT NULL,
      record bytea NOT NULL,
      PRIMARY KEY (record_key, object_hash)
    )
    """)

    {:atomic, :ok}
  end

  def transaction(fun) do
    if Repo.in_transaction?(), do: nested_transaction(fun), else: run_transaction(fun, @retries)
  end

  def sync_transaction(fun), do: transaction(fun)

  @spec abort(term()) :: no_return()
  def abort(reason), do: throw({__MODULE__, :abort, reason})

  defp run_transaction(fun, retries) do
    result =
      Repo.transact(fn ->
        SQL.query!(Repo, "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
        invoke(fun)
      end)

    case result do
      {:ok, value} -> {:atomic, value}
      {:error, reason} -> {:aborted, reason}
    end
  rescue
    error in Postgrex.Error ->
      if retries > 0 and retryable?(error) do
        Process.sleep(Enum.random(1..min(50, (@retries - retries + 1) * 5)))
        run_transaction(fun, retries - 1)
      else
        {:aborted, error}
      end

    error ->
      {:aborted, error}
  end

  defp nested_transaction(fun) do
    # PostgreSQL keeps older savepoints with the same name until the newer one
    # is released, so this also supports deeper nesting without process state.
    SQL.query!(Repo, "SAVEPOINT hex_hub_nested")

    result =
      case invoke(fun) do
        {:ok, value} ->
          {:atomic, value}

        {:error, reason} ->
          SQL.query!(Repo, "ROLLBACK TO SAVEPOINT hex_hub_nested")
          {:aborted, reason}
      end

    SQL.query!(Repo, "RELEASE SAVEPOINT hex_hub_nested")
    result
  end

  defp invoke(fun) do
    {:ok, fun.()}
  rescue
    error in Postgrex.Error ->
      # Serialization failures require retrying the entire transaction.
      if retryable?(error), do: reraise(error, __STACKTRACE__), else: {:error, error}

    error ->
      {:error, error}
  catch
    :throw, {__MODULE__, :abort, reason} -> {:error, reason}
    kind, reason -> {:error, {kind, reason}}
  end

  defp retryable?(%Postgrex.Error{postgres: %{code: code}}),
    do: code in [:serialization_failure, :deadlock_detected]

  defp retryable?(_error), do: false

  def read({table, key}), do: read(table, key)

  def read(table, key) do
    SQL.query!(Repo, "SELECT record FROM #{table_name(table)} WHERE record_key = $1", [
      encode(key)
    ])
    |> decode_rows()
  end

  def dirty_read(table, key), do: read(table, key)

  def write(record) do
    table = elem(record, 0)
    attributes = Keyword.fetch!(options(table), :attributes)

    if tuple_size(record) != length(attributes) + 1 do
      raise ArgumentError, "invalid record for #{table}"
    end

    data = encode(record)
    hash = if options(table)[:type] == :bag, do: :crypto.hash(:sha256, data), else: <<>>

    SQL.query!(
      Repo,
      """
      INSERT INTO #{table_name(table)} (record_key, object_hash, record)
      VALUES ($1, $2, $3)
      ON CONFLICT (record_key, object_hash) DO UPDATE SET record = EXCLUDED.record
      """,
      [encode(elem(record, 1)), hash, data]
    )

    :ok
  end

  def dirty_write(record), do: write(record)

  def delete({table, key}) do
    SQL.query!(Repo, "DELETE FROM #{table_name(table)} WHERE record_key = $1", [encode(key)])
    :ok
  end

  def dirty_delete(table, key), do: delete({table, key})

  def delete_object(record) do
    SQL.query!(
      Repo,
      "DELETE FROM #{table_name(elem(record, 0))} WHERE record_key = $1 AND record = $2",
      [encode(elem(record, 1)), encode(record)]
    )

    :ok
  end

  def match_object(pattern) do
    table = elem(pattern, 0)
    key = elem(pattern, 1)
    records = if literal_key?(key), do: read(table, key), else: all(table)
    :ets.match_spec_run(records, :ets.match_spec_compile([{pattern, [], [:"$_"]}]))
  end

  def dirty_match_object(pattern), do: match_object(pattern)
  def dirty_match_object(_table, pattern), do: match_object(pattern)

  def select(table, specification) do
    :ets.match_spec_run(all(table), :ets.match_spec_compile(specification))
  end

  def foldl(fun, acc, table), do: Enum.reduce(all(table), acc, fun)

  def index_read(table, value, attribute) do
    position = Enum.find_index(options(table)[:attributes], &(&1 == attribute))
    Enum.filter(all(table), &(elem(&1, position + 1) == value))
  end

  def clear_table(table) do
    SQL.query!(Repo, "DELETE FROM #{table_name(table)}")
    {:atomic, :ok}
  end

  def table_info(table, :size) do
    %{rows: [[count]]} = SQL.query!(Repo, "SELECT count(*) FROM #{table_name(table)}")
    count
  end

  def table_info(table, :attributes), do: options(table)[:attributes]

  def system_info(:is_running) do
    case SQL.query(Repo, "SELECT 1") do
      {:ok, _} -> :yes
      {:error, _} -> :no
    end
  rescue
    _ -> :no
  end

  def system_info(:tables) do
    tables = Schema.tables() ++ Keyword.keys(@search_tables)

    %{rows: rows} =
      SQL.query!(
        Repo,
        "SELECT name FROM unnest($1::text[]) AS tables(name) WHERE to_regclass(name) IS NOT NULL",
        [Enum.map(tables, &table_name/1)]
      )

    names = MapSet.new(rows, fn [name] -> name end)
    Enum.filter(tables, &MapSet.member?(names, table_name(&1)))
  end

  def wait_for_tables(tables, _timeout) do
    existing = system_info(:tables)

    case tables -- existing do
      [] -> :ok
      missing -> {:timeout, missing}
    end
  end

  defp all(table) do
    records = SQL.query!(Repo, "SELECT record FROM #{table_name(table)}") |> decode_rows()

    if options(table)[:type] == :ordered_set,
      do: Enum.sort_by(records, &elem(&1, 1)),
      else: records
  end

  defp table_name(table) do
    options(table)
    "hex_hub_#{table}"
  end

  defp options(table) do
    Keyword.fetch!(Schema.definitions() ++ @search_tables, table)
  end

  defp encode(term), do: :erlang.term_to_binary(term, [:deterministic])

  # Only records written by the application are decoded. Safe mode forbids new atoms.
  defp decode_rows(%{rows: rows}) do
    Enum.map(rows, fn [record] -> :erlang.binary_to_term(record, [:safe]) end)
  end

  defp literal_key?(:_), do: false
  defp literal_key?(key) when is_atom(key), do: not String.starts_with?(Atom.to_string(key), "$")

  defp literal_key?(key) when is_tuple(key),
    do: key |> Tuple.to_list() |> Enum.all?(&literal_key?/1)

  defp literal_key?(key) when is_list(key), do: Enum.all?(key, &literal_key?/1)
  defp literal_key?(key) when is_map(key), do: false
  defp literal_key?(_key), do: true
end
