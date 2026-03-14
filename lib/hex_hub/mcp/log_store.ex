defmodule HexHub.MCP.LogStore do
  @moduledoc """
  ETS-based ring buffer for storing recent MCP request logs.
  Keeps the last N entries for display in the admin dashboard.
  """

  use GenServer

  @table :mcp_logs
  @max_entries 500
  @counter_key :log_counter

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Log an MCP request with its result.
  """
  def log_request(entry) do
    GenServer.cast(__MODULE__, {:log, entry})
  end

  @doc """
  Get recent log entries, newest first.
  """
  def list_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    try do
      entries =
        :ets.tab2list(@table)
        |> Enum.reject(fn {key, _} -> key == @counter_key end)
        |> Enum.sort_by(fn {id, _} -> id end, :desc)
        |> Enum.drop(offset)
        |> Enum.take(limit)
        |> Enum.map(fn {_id, entry} -> entry end)

      total =
        case :ets.lookup(@table, @counter_key) do
          [{_, count}] -> min(count, @max_entries)
          [] -> 0
        end

      {:ok, entries, total}
    rescue
      ArgumentError -> {:ok, [], 0}
    end
  end

  @doc """
  Clear all logs.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Get log count.
  """
  def count do
    try do
      case :ets.lookup(@table, @counter_key) do
        [{_, count}] -> min(count, @max_entries)
        [] -> 0
      end
    rescue
      ArgumentError -> 0
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.insert(table, {@counter_key, 0})
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    counter =
      case :ets.lookup(@table, @counter_key) do
        [{_, c}] -> c + 1
        [] -> 1
      end

    :ets.insert(@table, {@counter_key, counter})

    log_entry =
      entry
      |> Map.put(:id, counter)
      |> Map.put_new(:timestamp, DateTime.utc_now())

    :ets.insert(@table, {counter, log_entry})

    # Evict old entries beyond max
    if counter > @max_entries do
      evict_id = counter - @max_entries
      :ets.delete(@table, evict_id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    :ets.insert(@table, {@counter_key, 0})
    {:reply, :ok, state}
  end
end