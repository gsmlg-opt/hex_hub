defmodule HexHub.ApiKeyCache do
  @moduledoc """
  ETS-based cache for API key validation.

  This cache stores recently validated API keys to avoid O(n) bcrypt
  comparisons on every request. Cache entries expire after a configurable TTL.

  ## How it works

  1. On first validation, we iterate through all keys and find the matching one
  2. After successful validation, we cache: key_hash -> {username, permissions, expires_at}
  3. On subsequent validations, we check the cache first
  4. Cache entries expire after TTL (default: 5 minutes)

  ## Security considerations

  - We use SHA256 hash of the key as cache key (not the raw key)
  - Cache entries have a short TTL to limit exposure if a key is revoked
  - Cache is cleared on key revocation
  """

  use GenServer

  @cache_table :api_key_cache
  # 5 minutes
  @default_ttl_ms 300_000
  # Cleanup every minute
  @cleanup_interval_ms 60_000

  ## Client API

  @doc """
  Start the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached validation result for a key.
  Returns {:ok, %{username: ..., permissions: ...}} or :not_found
  """
  @spec get(String.t()) :: {:ok, map()} | :not_found
  def get(key) do
    cache_key = hash_key(key)

    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, username, permissions, expires_at}] ->
        if System.system_time(:millisecond) < expires_at do
          {:ok, %{username: username, permissions: permissions}}
        else
          # Expired, remove it
          :ets.delete(@cache_table, cache_key)
          :not_found
        end

      [] ->
        :not_found
    end
  rescue
    ArgumentError ->
      # Table doesn't exist yet
      :not_found
  end

  @doc """
  Cache a successful validation result.
  """
  @spec put(String.t(), String.t(), [String.t()]) :: :ok
  def put(key, username, permissions) do
    cache_key = hash_key(key)
    ttl = Application.get_env(:hex_hub, :api_key_cache_ttl, @default_ttl_ms)
    expires_at = System.system_time(:millisecond) + ttl

    :ets.insert(@cache_table, {cache_key, username, permissions, expires_at})
    :ok
  rescue
    ArgumentError ->
      # Table doesn't exist yet
      :ok
  end

  @doc """
  Invalidate cache entries for a specific user (e.g., on key revocation).
  """
  @spec invalidate_user(String.t()) :: :ok
  def invalidate_user(username) do
    # Delete all entries for this user
    :ets.select_delete(@cache_table, [
      {{:_, :"$1", :_, :_}, [{:==, :"$1", username}], [true]}
    ])

    :ok
  rescue
    ArgumentError ->
      :ok
  end

  @doc """
  Clear all cache entries.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@cache_table)
    :ok
  rescue
    ArgumentError ->
      :ok
  end

  ## GenServer callbacks

  @impl GenServer
  def init(_opts) do
    # Create ETS table
    :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private functions

  defp hash_key(key) do
    :crypto.hash(:sha256, key)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired do
    now = System.system_time(:millisecond)

    :ets.select_delete(@cache_table, [
      {{:_, :_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])
  rescue
    ArgumentError ->
      :ok
  end
end
