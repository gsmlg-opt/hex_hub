defmodule HexHub.Storage do
  @moduledoc """
  Storage abstraction layer for handling package and documentation uploads.
  Supports both local filesystem storage and S3-compatible storage.
  """

  alias ExAws.S3
  alias HexHub.Telemetry

  @type storage_type :: :local | :s3
  @type upload_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Upload a file (package or documentation) to storage.
  """
  @spec upload(String.t(), binary(), Keyword.t()) :: upload_result
  def upload(key, content, opts \\ []) do
    storage_type = get_storage_type()
    upload_to_storage(storage_type, key, content, opts)
  end

  @doc """
  Download a file from storage.
  """
  @spec download(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def download(key) do
    storage_type = get_storage_type()
    download_from_storage(storage_type, key)
  end

  @doc """
  Delete a file from storage.
  """
  @spec delete(String.t()) :: :ok | {:error, String.t()}
  def delete(key) do
    storage_type = get_storage_type()
    delete_from_storage(storage_type, key)
  end

  @doc """
  Generate a signed URL for file download (S3 only).
  """
  @spec signed_url(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, String.t()}
  def signed_url(key, opts \\ []) do
    storage_type = get_storage_type()
    generate_signed_url(storage_type, key, opts)
  end

  @doc """
  Generate a storage key for package or documentation.
  """
  @spec generate_package_key(String.t(), String.t()) :: String.t()
  def generate_package_key(package_name, version) do
    "packages/#{package_name}-#{version}.tar.gz"
  end

  @spec generate_docs_key(String.t(), String.t()) :: String.t()
  def generate_docs_key(package_name, version) do
    "docs/#{package_name}-#{version}.tar.gz"
  end

  ## Private functions

  defp get_storage_type() do
    case Application.get_env(:hex_hub, :storage_type, :local) do
      "s3" -> :s3
      "local" -> :local
      type when is_atom(type) -> type
    end
  end

  defp upload_to_storage(:local, key, content, _opts) do
    start_time = System.monotonic_time()
    path = Path.join([storage_path(), key])

    result =
      case File.mkdir_p(Path.dirname(path)) do
        :ok ->
          case File.write(path, content) do
            :ok -> {:ok, key}
            {:error, reason} -> {:error, "Failed to write file: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to create directory: #{inspect(reason)}"}
      end

    duration_ms =
      (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

    case result do
      {:ok, _} ->
        HexHub.Telemetry.track_storage_operation(
          "upload",
          "local",
          duration_ms,
          byte_size(content)
        )

      {:error, _} ->
        HexHub.Telemetry.track_storage_operation("upload", "local", duration_ms, 0, "error")
    end

    result
  end

  defp upload_to_storage(:s3, key, content, opts) do
    bucket = get_s3_bucket()

    if bucket do
      start_time = System.monotonic_time()

      upload_opts = build_s3_upload_opts(opts)

      result =
        content
        |> S3.upload(bucket, key, upload_opts)
        |> ExAws.request()
        |> handle_s3_response("upload", key)

      duration_ms =
        (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, _} ->
          HexHub.Telemetry.track_storage_operation(
            "upload",
            "s3",
            duration_ms,
            byte_size(content)
          )

        {:error, _} ->
          HexHub.Telemetry.track_storage_operation("upload", "s3", duration_ms, 0, "error")
      end

      result
    else
      {:error, "S3 bucket not configured"}
    end
  end

  defp download_from_storage(:local, key) do
    start_time = System.monotonic_time()
    path = Path.join([storage_path(), key])

    result =
      case File.read(path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, "File not found"}
        {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
      end

    duration_ms =
      (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

    case result do
      {:ok, content} ->
        HexHub.Telemetry.track_storage_operation(
          "download",
          "local",
          duration_ms,
          byte_size(content)
        )

      {:error, _} ->
        HexHub.Telemetry.track_storage_operation("download", "local", duration_ms, 0, "error")
    end

    result
  end

  defp download_from_storage(:s3, key) do
    bucket = get_s3_bucket()

    if bucket do
      start_time = System.monotonic_time()

      result =
        bucket
        |> S3.get_object(key)
        |> ExAws.request()
        |> handle_s3_download_response(key)

      duration_ms =
        (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, content} ->
          HexHub.Telemetry.track_storage_operation(
            "download",
            "s3",
            duration_ms,
            byte_size(content)
          )

        {:error, _} ->
          HexHub.Telemetry.track_storage_operation("download", "s3", duration_ms, 0, "error")
      end

      result
    else
      {:error, "S3 bucket not configured"}
    end
  end

  defp delete_from_storage(:local, key) do
    start_time = System.monotonic_time()
    path = Path.join([storage_path(), key])

    result =
      case File.rm(path) do
        :ok -> :ok
        # Already deleted
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, "Failed to delete file: #{inspect(reason)}"}
      end

    duration_ms =
      (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

    case result do
      :ok ->
        HexHub.Telemetry.track_storage_operation("delete", "local", duration_ms, 0)

      {:error, _} ->
        HexHub.Telemetry.track_storage_operation("delete", "local", duration_ms, 0, "error")
    end

    result
  end

  defp delete_from_storage(:s3, key) do
    bucket = get_s3_bucket()

    if bucket do
      start_time = System.monotonic_time()

      result =
        bucket
        |> S3.delete_object(key)
        |> ExAws.request()
        |> handle_s3_response("delete", key)

      duration_ms =
        (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, _} ->
          HexHub.Telemetry.track_storage_operation("delete", "s3", duration_ms, 0)

        {:error, _} ->
          HexHub.Telemetry.track_storage_operation("delete", "s3", duration_ms, 0, "error")
      end

      result
    else
      {:error, "S3 bucket not configured"}
    end
  end

  defp storage_path() do
    Application.get_env(:hex_hub, :storage_path, "priv/storage")
  end

  defp get_s3_bucket() do
    Application.get_env(:hex_hub, :s3_bucket)
  end

  defp build_s3_upload_opts(opts) do
    base_opts = [
      acl: :private,
      content_type: Keyword.get(opts, :content_type, "application/octet-stream")
    ]

    # Add encryption if specified
    if Keyword.get(opts, :encrypt, true) do
      Keyword.put(base_opts, :server_side_encryption, "AES256")
    else
      base_opts
    end
  end

  defp handle_s3_response({:ok, _response}, operation, key) do
    Telemetry.log(:debug, :storage, "S3 operation successful", %{operation: operation, key: key})
    {:ok, key}
  end

  defp handle_s3_response({:error, error}, operation, key) do
    Telemetry.log(:error, :storage, "S3 operation failed", %{
      operation: operation,
      key: key,
      error: inspect(error)
    })

    {:error, format_s3_error(error)}
  end

  defp handle_s3_download_response({:ok, %{body: body}}, _key) do
    {:ok, body}
  end

  defp handle_s3_download_response({:error, error}, key) do
    Telemetry.log(:error, :storage, "S3 download failed", %{key: key, error: inspect(error)})
    {:error, format_s3_error(error)}
  end

  defp format_s3_error({:http_error, status_code, body}) when is_binary(body) do
    try do
      error_data = Jason.decode!(body)
      "S3 error (#{status_code}): #{error_data["message"] || "Unknown error"}"
    rescue
      _ -> "S3 error (#{status_code}): #{body}"
    end
  end

  defp format_s3_error({:http_error, status_code, _body}) do
    "S3 error (#{status_code}): HTTP request failed"
  end

  defp format_s3_error(error) do
    "S3 error: #{inspect(error)}"
  end

  defp generate_signed_url(:local, _key, _opts) do
    {:error, "Signed URLs not supported for local storage"}
  end

  defp generate_signed_url(:s3, key, opts) do
    bucket = get_s3_bucket()

    if bucket do
      # 1 hour default
      expires_in = Keyword.get(opts, :expires_in, 3600)

      # Use ExAws to generate a presigned URL
      config = ExAws.Config.new(:s3)

      case ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: expires_in) do
        {:ok, url} -> {:ok, url}
        {:error, error} -> {:error, format_s3_error(error)}
      end
    else
      {:error, "S3 bucket not configured"}
    end
  end

  @doc """
  Check if a file exists in storage.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) do
    storage_type = get_storage_type()
    exists_in_storage?(storage_type, key)
  end

  # Private helper functions

  defp exists_in_storage?(:local, key) do
    file_path = Path.join([storage_path(), key])
    File.exists?(file_path)
  end

  defp exists_in_storage?(:s3, key) do
    bucket = get_s3_bucket()

    if bucket do
      # Use ExAws default configuration (already set in runtime.exs)
      case ExAws.S3.head_object(bucket, key) |> ExAws.request() do
        {:ok, _} -> true
        {:error, _} -> false
      end
    else
      false
    end
  end

  @doc """
  Get file content from storage.
  """
  @spec get(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def get(key) do
    download(key)
  end
end
