defmodule HexHub.PublishConfig do
  @moduledoc """
  Publish configuration management module.

  Handles storage and retrieval of anonymous publish configuration settings
  in the configured metadata database.
  """

  alias HexHub.Telemetry

  @type t :: %{
          id: String.t(),
          enabled: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc """
  Get the current publish configuration from the database.
  Returns default config if no configuration exists or table is not yet created.
  """
  @spec get_config() :: t()
  def get_config do
    # Check if table exists first to handle startup race conditions
    case table_exists?(:publish_configs) do
      false ->
        get_default_config()

      true ->
        case HexHub.Database.dirty_read(:publish_configs, "default") do
          [] ->
            # Return default configuration if none exists
            get_default_config()

          [{:publish_configs, "default", enabled, inserted_at, updated_at}] ->
            %{
              id: "default",
              enabled: enabled,
              inserted_at: DateTime.from_unix!(inserted_at),
              updated_at: DateTime.from_unix!(updated_at)
            }
        end
    end
  end

  @doc """
  Update the publish configuration.
  """
  @spec update_config(map()) :: :ok | {:error, term()}
  def update_config(params) do
    # Check if table exists first
    if table_exists?(:publish_configs) do
      do_update_config(params)
    else
      Telemetry.log(:warning, :config, "Cannot update publish config: table does not exist", %{})
      {:error, :table_not_exists}
    end
  end

  defp do_update_config(params) do
    # Get existing config to merge with
    existing_config = get_config()
    current_time = DateTime.utc_now()

    # Handle both string and atom keys from form submissions
    enabled = get_param_bool(params, "enabled", existing_config.enabled)
    previous_enabled = existing_config.enabled

    config = %{
      id: "default",
      enabled: enabled,
      inserted_at: existing_config.inserted_at,
      updated_at: current_time
    }

    record = {
      :publish_configs,
      config.id,
      config.enabled,
      DateTime.to_unix(config.inserted_at),
      DateTime.to_unix(config.updated_at)
    }

    # Use sync_transaction to ensure config is persisted to disc immediately
    # This is important for disc_copies tables to survive process restarts
    case HexHub.Database.sync_transaction(fn ->
           HexHub.Database.write(record)
         end) do
      {:atomic, :ok} ->
        # Emit telemetry event for config change
        :telemetry.execute(
          [:hex_hub, :publish_config, :updated],
          %{},
          %{
            enabled: config.enabled,
            previous_enabled: previous_enabled
          }
        )

        Telemetry.log(:info, :config, "Publish configuration updated", %{
          enabled: config.enabled,
          previous: previous_enabled
        })

        :ok

      {:aborted, reason} ->
        Telemetry.log(:error, :config, "Failed to update publish configuration", %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Check if anonymous publishing is enabled.
  """
  @spec anonymous_publishing_enabled?() :: boolean()
  def anonymous_publishing_enabled? do
    get_config().enabled
  end

  @doc """
  Initialize default publish configuration if it doesn't exist.
  """
  @spec init_default_config() :: :ok | {:error, term()}
  def init_default_config do
    # Ensure table exists before trying to read
    case table_exists?(:publish_configs) do
      false ->
        # Table doesn't exist yet, skip initialization
        # (will be created during database initialization and config will use defaults)
        :ok

      true ->
        case HexHub.Database.dirty_read(:publish_configs, "default") do
          [] ->
            # Create default config (disabled by default per FR-003)
            update_config(%{"enabled" => false})

          [_] ->
            :ok
        end
    end
  end

  # Private functions

  defp table_exists?(table) do
    HexHub.Database.system_info(:tables) |> Enum.member?(table)
  end

  defp get_param_bool(params, key, default) do
    cond do
      Map.has_key?(params, key) ->
        parse_bool(Map.get(params, key), default)

      Map.has_key?(params, String.to_atom(key)) ->
        parse_bool(Map.get(params, String.to_atom(key)), default)

      true ->
        default
    end
  end

  defp parse_bool("true", _default), do: true
  defp parse_bool("false", _default), do: false
  defp parse_bool(true, _default), do: true
  defp parse_bool(false, _default), do: false
  defp parse_bool(_, default), do: default

  defp get_default_config do
    current_time = DateTime.utc_now()

    %{
      id: "default",
      enabled: false,
      inserted_at: current_time,
      updated_at: current_time
    }
  end
end
