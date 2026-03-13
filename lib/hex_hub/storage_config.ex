defmodule HexHub.StorageConfig do
  @moduledoc """
  Storage configuration management for HexHub.
  Persists configuration to Mnesia so it survives application restarts.
  Also applies config to Application env so ExAws and the rest of the app work.
  """

  alias HexHub.Telemetry

  @doc """
  Get the current storage configuration from Mnesia.
  Falls back to Application env defaults if no Mnesia record exists.
  """
  @spec config() :: map()
  def config do
    case :mnesia.dirty_read(:storage_configs, "default") do
      [] ->
        get_default_config()

      [{:storage_configs, "default", storage_type, storage_path, s3_bucket, s3_bucket_path,
        s3_region, s3_host, s3_port, s3_scheme, s3_path_style, s3_access_key_id,
        s3_secret_access_key, inserted_at, updated_at}] ->
        %{
          id: "default",
          storage_type: storage_type,
          storage_path: storage_path,
          s3_bucket: s3_bucket,
          s3_bucket_path: s3_bucket_path,
          s3_region: s3_region,
          s3_host: s3_host,
          s3_port: s3_port,
          s3_scheme: s3_scheme,
          s3_path_style: s3_path_style,
          s3_access_key_id: s3_access_key_id,
          s3_secret_access_key: s3_secret_access_key,
          inserted_at: DateTime.from_unix!(inserted_at),
          updated_at: DateTime.from_unix!(updated_at)
        }
    end
  rescue
    # Mnesia may not be ready during early startup
    _ -> get_default_config()
  end

  @doc """
  Test the current storage configuration.
  """
  @spec test_connection() :: {:ok, String.t()} | {:error, String.t()}
  def test_connection do
    storage_config = config()

    case storage_config.storage_type do
      :local ->
        test_local_storage(storage_config)

      :s3 ->
        test_s3_storage(storage_config)

      _ ->
        {:error, "Invalid storage type: #{storage_config.storage_type}"}
    end
  end

  @doc """
  Update storage configuration. Persists to Mnesia and applies to Application env.
  """
  @spec update_config(map()) :: :ok | {:error, String.t()}
  def update_config(params) do
    existing = config()
    current_time = DateTime.utc_now()

    storage_type =
      case params["storage_type"] do
        nil -> existing.storage_type
        val when is_binary(val) -> String.to_existing_atom(val)
        val when is_atom(val) -> val
      end

    storage_path = params["storage_path"] || existing.storage_path
    s3_bucket = params["s3_bucket"] || existing.s3_bucket
    s3_bucket_path = params["s3_bucket_path"] || existing.s3_bucket_path
    s3_region = params["s3_region"] || existing.s3_region
    s3_host = params["s3_host"]
    s3_port = parse_port(params["s3_port"], existing.s3_port)
    s3_scheme = params["s3_scheme"] || existing.s3_scheme
    s3_path_style = parse_bool(params["s3_path_style"], existing.s3_path_style)

    # Only update credentials when provided (non-empty), to avoid clearing existing values
    s3_access_key_id =
      case params["s3_access_key_id"] do
        val when is_binary(val) and val != "" -> val
        _ -> existing.s3_access_key_id
      end

    s3_secret_access_key =
      case params["s3_secret_access_key"] do
        val when is_binary(val) and val != "" -> val
        _ -> existing.s3_secret_access_key
      end

    # Validate
    if storage_type == :s3 and (s3_bucket == nil or s3_bucket == "") do
      {:error, "S3 bucket is required when using S3 storage"}
    else
      inserted_at = Map.get(existing, :inserted_at, current_time)

      record =
        {:storage_configs, "default", storage_type, storage_path, s3_bucket, s3_bucket_path,
         s3_region, s3_host, s3_port, s3_scheme, s3_path_style, s3_access_key_id,
         s3_secret_access_key, DateTime.to_unix(inserted_at), DateTime.to_unix(current_time)}

      case :mnesia.sync_transaction(fn -> :mnesia.write(record) end) do
        {:atomic, :ok} ->
          # Apply to Application env so ExAws and the rest of the app pick it up
          apply_to_app_env()

          Telemetry.log(:info, :storage, "Storage configuration updated", %{
            storage_type: storage_type
          })

          :ok

        {:aborted, reason} ->
          Telemetry.log(:error, :storage, "Failed to update storage configuration", %{
            reason: inspect(reason)
          })

          {:error, inspect(reason)}
      end
    end
  end

  @doc """
  Initialize default storage configuration from Application env if no Mnesia record exists.
  Called on application startup.
  """
  @spec init_default_config() :: :ok | {:error, term()}
  def init_default_config do
    case :mnesia.dirty_read(:storage_configs, "default") do
      [] ->
        # Seed Mnesia from current Application env (set by config/runtime.exs)
        seed_from_app_env()

      [_] ->
        # Mnesia already has config — apply it to Application env
        apply_to_app_env()
        :ok
    end
  end

  @doc """
  Apply Mnesia-stored config to Application env so ExAws and HexHub modules work.
  """
  @spec apply_to_app_env() :: :ok
  def apply_to_app_env do
    cfg = config()

    Application.put_env(:hex_hub, :storage_type, cfg.storage_type)
    Application.put_env(:hex_hub, :storage_path, cfg.storage_path)
    Application.put_env(:hex_hub, :s3_bucket, cfg.s3_bucket)
    Application.put_env(:hex_hub, :s3_bucket_path, cfg.s3_bucket_path)
    Application.put_env(:hex_hub, :s3_region, cfg.s3_region)

    if cfg.s3_access_key_id do
      Application.put_env(:ex_aws, :access_key_id, cfg.s3_access_key_id)
    end

    if cfg.s3_secret_access_key do
      Application.put_env(:ex_aws, :secret_access_key, cfg.s3_secret_access_key)
    end

    s3_config =
      [
        scheme: cfg.s3_scheme,
        port: cfg.s3_port,
        path_style: cfg.s3_path_style
      ]
      |> then(fn opts ->
        if cfg.s3_host && cfg.s3_host != "" do
          Keyword.put(opts, :host, cfg.s3_host)
        else
          opts
        end
      end)

    current_s3 = Application.get_env(:ex_aws, :s3, [])

    current_s3 =
      if not Keyword.has_key?(s3_config, :host) do
        Keyword.delete(current_s3, :host)
      else
        current_s3
      end

    Application.put_env(:ex_aws, :s3, Keyword.merge(current_s3, s3_config))
    :ok
  end

  # Private functions

  defp seed_from_app_env do
    s3_config = Application.get_env(:ex_aws, :s3, [])
    ex_aws_config = Application.get_all_env(:ex_aws)

    params = %{
      "storage_type" => to_string(Application.get_env(:hex_hub, :storage_type, :local)),
      "storage_path" => Application.get_env(:hex_hub, :storage_path, "priv/storage"),
      "s3_bucket" => Application.get_env(:hex_hub, :s3_bucket),
      "s3_bucket_path" => Application.get_env(:hex_hub, :s3_bucket_path, "/"),
      "s3_region" => Application.get_env(:hex_hub, :s3_region, "us-east-1"),
      "s3_host" => Keyword.get(s3_config, :host),
      "s3_port" => to_string(Keyword.get(s3_config, :port, 443)),
      "s3_scheme" => Keyword.get(s3_config, :scheme, "https://"),
      "s3_path_style" => to_string(Keyword.get(s3_config, :path_style, false)),
      "s3_access_key_id" => Keyword.get(ex_aws_config, :access_key_id),
      "s3_secret_access_key" => Keyword.get(ex_aws_config, :secret_access_key)
    }

    update_config(params)
  end

  defp get_default_config do
    s3_config = Application.get_env(:ex_aws, :s3, [])
    ex_aws_config = Application.get_all_env(:ex_aws)

    %{
      storage_type: Application.get_env(:hex_hub, :storage_type, :local),
      storage_path: Application.get_env(:hex_hub, :storage_path, "priv/storage"),
      s3_bucket: Application.get_env(:hex_hub, :s3_bucket),
      s3_bucket_path: Application.get_env(:hex_hub, :s3_bucket_path, "/"),
      s3_region: Application.get_env(:hex_hub, :s3_region, "us-east-1"),
      s3_host: Keyword.get(s3_config, :host),
      s3_port: Keyword.get(s3_config, :port),
      s3_scheme: Keyword.get(s3_config, :scheme, "https://"),
      s3_path_style: Keyword.get(s3_config, :path_style, false),
      s3_access_key_id: Keyword.get(ex_aws_config, :access_key_id),
      s3_secret_access_key: Keyword.get(ex_aws_config, :secret_access_key)
    }
  end

  defp parse_port(nil, default), do: default
  defp parse_port("", default), do: default

  defp parse_port(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {port, ""} -> port
      _ -> default
    end
  end

  defp parse_port(val, _default) when is_integer(val), do: val

  defp parse_bool(nil, default), do: default
  defp parse_bool("true", _), do: true
  defp parse_bool("false", _), do: false
  defp parse_bool(val, _) when is_boolean(val), do: val
  defp parse_bool(_, default), do: default

  defp test_local_storage(config) do
    storage_path = config.storage_path

    case File.mkdir_p(storage_path) do
      :ok ->
        test_file = Path.join(storage_path, ".storage_test_#{System.system_time()}")
        test_content = "Storage test file"

        case File.write(test_file, test_content) do
          :ok ->
            case File.read(test_file) do
              {:ok, ^test_content} ->
                File.rm(test_file)
                {:ok, "Local storage working correctly"}

              {:ok, _} ->
                File.rm(test_file)
                {:error, "Storage read test failed"}

              {:error, reason} ->
                {:error, "Storage read test failed: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Storage write test failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Cannot create storage directory: #{reason}"}
    end
  end

  defp test_s3_storage(config) do
    if config.s3_bucket == nil or config.s3_bucket == "" do
      {:error, "S3 bucket not configured"}
    else
      task =
        Task.async(fn ->
          try do
            case ExAws.S3.list_objects(config.s3_bucket, max_keys: 1) |> ExAws.request() do
              {:ok, _result} ->
                {:ok, "S3 connection working correctly"}

              {:error, reason} ->
                {:error, "S3 connection failed: #{inspect(reason)}"}
            end
          rescue
            UndefinedFunctionError ->
              {:error, "ExAws.S3 not available - check S3 dependencies"}

            e ->
              {:error, "S3 connection failed: #{Exception.message(e)}"}
          end
        end)

      case Task.yield(task, 10_000) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, "S3 connection timed out after 10 seconds"}
      end
    end
  end
end
