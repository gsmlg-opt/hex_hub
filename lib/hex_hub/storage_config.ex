defmodule HexHub.StorageConfig do
  @moduledoc """
  Storage configuration management for HexHub.
  Provides centralized access to storage configuration settings.
  """

  @doc """
  Get the current storage configuration.
  """
  @spec config() :: %{
          storage_type: atom(),
          storage_path: String.t(),
          s3_bucket: String.t() | nil,
          s3_bucket_path: String.t(),
          s3_region: String.t() | nil,
          s3_host: String.t() | nil,
          s3_port: integer() | nil,
          s3_scheme: String.t(),
          s3_path_style: boolean()
        }
  def config do
    s3_config = Application.get_env(:ex_aws, :s3, [])

    %{
      storage_type: Application.get_env(:hex_hub, :storage_type, :local),
      storage_path: Application.get_env(:hex_hub, :storage_path, "priv/storage"),
      s3_bucket: Application.get_env(:hex_hub, :s3_bucket),
      s3_bucket_path: Application.get_env(:hex_hub, :s3_bucket_path, "/"),
      s3_region: Application.get_env(:hex_hub, :s3_region, "us-east-1"),
      s3_host: Keyword.get(s3_config, :host),
      s3_port: Keyword.get(s3_config, :port),
      s3_scheme: Keyword.get(s3_config, :scheme, "https://"),
      s3_path_style: Keyword.get(s3_config, :path_style, false)
    }
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
  Update storage configuration.
  """
  @spec update_config(map()) :: :ok | {:error, String.t()}
  def update_config(params) do
    try do
      # Convert string parameters to appropriate types
      storage_type = String.to_atom(params["storage_type"] || "local")
      storage_path = params["storage_path"] || "priv/storage"
      s3_bucket = params["s3_bucket"]
      s3_bucket_path = params["s3_bucket_path"] || "/"
      s3_region = params["s3_region"] || "us-east-1"
      s3_host = params["s3_host"]
      s3_port = if port = params["s3_port"], do: String.to_integer(port), else: nil
      s3_scheme = params["s3_scheme"] || "https://"
      s3_path_style = params["s3_path_style"] == "true"

      # Validate configuration
      if storage_type == :s3 and (s3_bucket == nil or s3_bucket == "") do
        throw({:error, "S3 bucket is required when using S3 storage"})
      end

      if storage_type == :s3 and (s3_host == nil or s3_host == "") do
        throw({:error, "S3 host is required when using S3 storage"})
      end

      # Update hex_hub configuration
      Application.put_env(:hex_hub, :storage_type, storage_type)
      Application.put_env(:hex_hub, :storage_path, storage_path)
      Application.put_env(:hex_hub, :s3_bucket, s3_bucket)
      Application.put_env(:hex_hub, :s3_bucket_path, s3_bucket_path)
      Application.put_env(:hex_hub, :s3_region, s3_region)

      # Update ExAws S3 configuration
      s3_config = %{
        scheme: s3_scheme,
        host: s3_host,
        port: s3_port,
        path_style: s3_path_style
      }

      # Get current ExAws configuration
      current_s3_config = Application.get_env(:ex_aws, :s3, [])
      updated_s3_config = Keyword.merge(current_s3_config, Enum.into(s3_config, []))
      Application.put_env(:ex_aws, :s3, updated_s3_config)

      :ok
    catch
      {:error, reason} -> {:error, reason}
      :exit, _ -> {:error, "Invalid configuration parameters"}
      _ -> {:error, "Unknown error occurred"}
    end
  end

  # Private functions

  defp test_local_storage(config) do
    storage_path = config.storage_path

    case File.mkdir_p(storage_path) do
      :ok ->
        # Test write/read/delete operations
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
      # Test S3 connection by trying to list bucket
      try do
        require ExAws.S3

        case ExAws.S3.list_objects(config.s3_bucket) |> ExAws.request() do
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
    end
  end
end
