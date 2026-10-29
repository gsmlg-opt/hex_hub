defmodule HexHubWeb.Plugs.ETag do
  @moduledoc """
  ETag support for efficient caching of registry and package files.

  Implements:
  - ETag generation for responses
  - If-None-Match header handling
  - 304 Not Modified responses
  - Cache-Control headers
  """

  import Plug.Conn

  @default_cache_control "public, max-age=3600"
  @registry_cache_control "public, max-age=60, must-revalidate"
  # 1 year for immutable packages
  @package_cache_control "public, max-age=31536000, immutable"

  def init(opts), do: opts

  def call(conn, opts) do
    cache_control = opts[:cache_control] || determine_cache_control(conn)

    conn
    |> put_resp_header("cache-control", cache_control)
    |> handle_etag(opts)
  end

  @doc """
  Generate ETag from response body or file content.
  """
  def generate_etag(content) when is_binary(content) do
    hash =
      :crypto.hash(:md5, content)
      |> Base.encode16(case: :lower)

    "\"#{hash}\""
  end

  def generate_etag(%{path: path}) do
    case File.read(path) do
      {:ok, content} -> generate_etag(content)
      _ -> nil
    end
  end

  def generate_etag(_), do: nil

  @doc """
  Handle ETag validation and conditional requests.
  """
  def handle_etag(conn, _opts) do
    register_before_send(conn, fn conn ->
      case get_resp_header(conn, "etag") do
        [] ->
          # Generate ETag from response body if not already set
          maybe_add_etag(conn)

        [etag] ->
          # ETag already set, check if-none-match
          check_if_none_match(conn, etag)
      end
    end)
  end

  @doc """
  Set ETag header on connection.
  """
  def set_etag(conn, etag) when is_binary(etag) do
    put_resp_header(conn, "etag", etag)
  end

  def set_etag(conn, content) do
    case generate_etag(content) do
      nil -> conn
      etag -> put_resp_header(conn, "etag", etag)
    end
  end

  # Private functions

  defp determine_cache_control(conn) do
    cond do
      # Registry endpoints need shorter cache with revalidation
      String.contains?(conn.request_path, ["/names", "/versions", "/packages"]) ->
        @registry_cache_control

      # Package tarballs are immutable
      String.contains?(conn.request_path, "/tarballs/") ->
        @package_cache_control

      # Downloads are immutable
      String.contains?(conn.request_path, "/download") ->
        @package_cache_control

      # Default cache control
      true ->
        @default_cache_control
    end
  end

  defp maybe_add_etag(conn) do
    # Only add ETag for successful responses
    if conn.status in 200..299 do
      case get_response_body(conn) do
        nil ->
          conn

        body when is_binary(body) ->
          etag = generate_etag(body)

          put_resp_header(conn, "etag", etag)
          |> check_if_none_match(etag)
      end
    else
      conn
    end
  end

  defp check_if_none_match(conn, etag) do
    if_none_match = get_req_header(conn, "if-none-match")

    if etag_matches?(etag, if_none_match) do
      # Return 304 Not Modified
      conn
      |> put_status(304)
      |> delete_resp_header("content-type")
      |> delete_resp_header("content-length")
      |> halt()
    else
      conn
    end
  end

  defp etag_matches?(_etag, []), do: false

  defp etag_matches?(etag, [if_none_match | rest]) do
    # Handle multiple ETags in If-None-Match header
    if_none_match
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.any?(fn candidate ->
      candidate == "*" || candidate == etag
    end) || etag_matches?(etag, rest)
  end

  defp get_response_body(%{resp_body: body}) when is_binary(body), do: body
  defp get_response_body(_), do: nil
end

defmodule HexHubWeb.Plugs.RegistryCache do
  @moduledoc """
  Registry-specific caching with versioning and invalidation.
  """

  import Plug.Conn
  alias HexHubWeb.Plugs.ETag

  @registry_version_key "registry_version"

  def init(opts), do: opts

  def call(conn, _opts) do
    # Add registry version to responses for cache invalidation
    registry_version = get_registry_version()

    conn
    |> put_resp_header("x-hex-registry-version", to_string(registry_version))
    |> handle_registry_cache()
  end

  @doc """
  Get current registry version.
  """
  def get_registry_version() do
    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({:system_metadata, @registry_version_key}) do
             [{:system_metadata, @registry_version_key, version}] -> version
             [] -> 1
           end
         end) do
      {:atomic, version} -> version
      _ -> 1
    end
  end

  @doc """
  Increment registry version (invalidates all caches).
  """
  def increment_registry_version() do
    HexHub.Database.transaction(fn ->
      new_version = get_registry_version() + 1
      HexHub.Database.write({:system_metadata, @registry_version_key, new_version})
      new_version
    end)
  end

  @doc """
  Generate registry-specific ETag including version.
  """
  def generate_registry_etag(content) do
    version = get_registry_version()
    base_etag = ETag.generate_etag(content)

    case base_etag do
      nil ->
        nil

      etag ->
        # Strip quotes, add version, re-quote
        etag_value = String.trim(etag, "\"")
        "\"#{version}-#{etag_value}\""
    end
  end

  # Private functions

  defp handle_registry_cache(conn) do
    # Check if this is a registry endpoint
    if is_registry_endpoint?(conn) do
      register_before_send(conn, fn conn ->
        # Add registry-specific ETag
        case get_response_body(conn) do
          nil ->
            conn

          body ->
            etag = generate_registry_etag(body)

            if etag do
              put_resp_header(conn, "etag", etag)
            else
              conn
            end
        end
      end)
    else
      conn
    end
  end

  defp is_registry_endpoint?(conn) do
    String.contains?(conn.request_path, ["/names", "/versions", "/packages"])
  end

  defp get_response_body(%{resp_body: body}) when is_binary(body), do: body
  defp get_response_body(_), do: nil
end

defmodule HexHubWeb.Plugs.StaleCache do
  @moduledoc """
  Implements stale-while-revalidate caching strategy for improved performance.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    max_age = opts[:max_age] || 3600
    # 24 hours
    stale_while_revalidate = opts[:stale_while_revalidate] || 86400

    cache_control = "public, max-age=#{max_age}, stale-while-revalidate=#{stale_while_revalidate}"

    put_resp_header(conn, "cache-control", cache_control)
  end
end
