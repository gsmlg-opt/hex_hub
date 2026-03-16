defmodule HexHubWeb.API.RegistryController do
  @moduledoc """
  Controller for Hex registry endpoints.

  These endpoints serve the registry data in the format expected by the Hex client:
  - /names - All package names (gzipped protobuf)
  - /versions - All package versions (gzipped protobuf)
  - /packages/:name - Package registry data (gzipped protobuf)

  Responses are proxied from upstream hex.pm and cached locally in Mnesia.
  When upstream is unavailable, cached responses are served as fallback.
  """

  use HexHubWeb, :controller

  alias HexHub.Telemetry

  @registry_cache_table :registry_cache

  @doc """
  Serves the package names registry.

  Returns a gzipped protobuf of all package names.
  Proxies from upstream, with local cache fallback.
  """
  def names(conn, _params) do
    serve_registry(conn, "/names")
  end

  @doc """
  Serves the package versions registry.

  Returns a gzipped protobuf of all package versions.
  Proxies from upstream, with local cache fallback.
  """
  def versions(conn, _params) do
    serve_registry(conn, "/versions")
  end

  @doc """
  Serves the package registry data.

  Returns gzipped protobuf of package info including releases.
  Proxies from upstream, with local cache fallback.
  """
  def package(conn, %{"name" => name}) do
    serve_registry(conn, "/packages/#{name}")
  end

  # Unified registry serving with cache-through pattern
  defp serve_registry(conn, path) do
    case fetch_upstream_registry(path) do
      {:ok, data, headers} ->
        # Cache the successful response asynchronously
        cache_registry_response(path, data, headers)
        send_registry_response(conn, data, headers)

      {:error, reason} ->
        # Try to serve from cache
        case get_cached_registry(path) do
          {:ok, data, headers} ->
            Telemetry.log(:info, :api, "Serving registry from cache (upstream unavailable)", %{
              path: path,
              reason: reason
            })

            send_registry_response(conn, data, headers)

          :miss ->
            Telemetry.log(:warning, :api, "Registry request failed, no cache available", %{
              path: path,
              reason: reason
            })

            conn
            |> put_status(:bad_gateway)
            |> json(%{message: "Failed to fetch registry data from upstream"})
        end
    end
  end

  # Private functions

  defp fetch_upstream_registry(path) do
    config = HexHub.Upstream.config()

    if not config.enabled do
      {:error, "Upstream is disabled"}
    else
      # Use the repo_url for registry endpoints (not api_url)
      url = "#{config.repo_url}#{path}"

      headers = [
        {"user-agent", "HexHub/#{Application.spec(:hex_hub, :vsn)} (Registry-Proxy)"},
        {"accept", "application/octet-stream"}
      ]

      req_opts = [
        receive_timeout: config.timeout,
        headers: headers,
        # Disable automatic decompression - we want the raw gzipped data
        decode_body: false,
        compressed: false
      ]

      case Req.get(url, req_opts) do
        {:ok, %{status: 200, body: body, headers: resp_headers}} ->
          # Extract relevant headers for proxying
          relevant_headers = extract_relevant_headers(resp_headers)
          {:ok, body, relevant_headers}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status}} ->
          {:error, "Upstream returned status #{status}"}

        {:error, %Req.TransportError{reason: reason}} ->
          {:error, "Network error: #{inspect(reason)}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  defp extract_relevant_headers(headers) do
    # Extract headers that should be proxied
    headers
    |> Enum.filter(fn {name, _value} ->
      String.downcase(name) in [
        "content-type",
        "content-encoding",
        "etag",
        "cache-control",
        "last-modified"
      ]
    end)
    |> Enum.map(fn {name, value} ->
      # Normalize header names to lowercase
      {String.downcase(name), value}
    end)
  end

  defp send_registry_response(conn, data, headers) do
    # Apply proxied headers
    conn =
      Enum.reduce(headers, conn, fn {name, value}, acc ->
        # Handle list values (Req returns headers as lists)
        header_value =
          case value do
            [v | _] -> v
            v when is_binary(v) -> v
            v -> to_string(v)
          end

        put_resp_header(acc, name, header_value)
      end)

    # Ensure we have proper content-type if not set
    conn =
      if get_resp_header(conn, "content-type") == [] do
        put_resp_content_type(conn, "application/octet-stream")
      else
        conn
      end

    send_resp(conn, 200, data)
  end

  # Cache a registry response in Mnesia for offline fallback
  defp cache_registry_response(path, data, headers) do
    record =
      {@registry_cache_table, path, data, headers, System.system_time(:second)}

    # Fire-and-forget write - don't block the response
    spawn(fn ->
      case :mnesia.transaction(fn -> :mnesia.write(record) end) do
        {:atomic, :ok} ->
          :ok

        {:aborted, reason} ->
          Telemetry.log(:warning, :api, "Failed to cache registry response", %{
            path: path,
            reason: inspect(reason)
          })
      end
    end)
  end

  # Retrieve a cached registry response from Mnesia
  defp get_cached_registry(path) do
    case :mnesia.dirty_read(@registry_cache_table, path) do
      [{@registry_cache_table, ^path, data, headers, _cached_at}] ->
        {:ok, data, headers}

      [] ->
        :miss
    end
  rescue
    _ -> :miss
  end
end
