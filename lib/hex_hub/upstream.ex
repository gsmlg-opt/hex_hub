defmodule HexHub.Upstream do
  @moduledoc """
  Upstream package fetching functionality for HexHub.

  This module handles fetching packages and metadata from an upstream hex repository
  when they are not found locally. It supports retry logic, proper error handling,
  and telemetry tracking.
  """

  alias HexHub.{Storage, Telemetry, UpstreamConfig}

  @type upstream_config :: %{
          enabled: boolean(),
          api_url: String.t(),
          repo_url: String.t(),
          api_key: String.t() | nil,
          timeout: integer(),
          retry_attempts: integer(),
          retry_delay: integer()
        }

  @doc """
  Get the current upstream configuration from the database.
  """
  @spec config() :: upstream_config()
  def config do
    db_config = UpstreamConfig.get_config()

    %{
      enabled: db_config.enabled,
      api_url: db_config.api_url,
      repo_url: db_config.repo_url,
      api_key: db_config.api_key,
      timeout: db_config.timeout,
      retry_attempts: db_config.retry_attempts,
      retry_delay: db_config.retry_delay
    }
  end

  @doc """
  Check if upstream functionality is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    UpstreamConfig.enabled?()
  end

  @doc """
  Check if upstream API key is configured.
  """
  @spec api_key_configured?() :: boolean()
  def api_key_configured? do
    UpstreamConfig.api_key_configured?()
  end

  @doc """
  Fetch package metadata from upstream.
  """
  @spec fetch_package(String.t()) :: {:ok, map()} | {:error, String.t()}
  def fetch_package(package_name) do
    upstream_config = config()

    if not upstream_config.enabled do
      {:error, "Upstream is disabled"}
    else
      start_time = System.monotonic_time()
      url = "#{upstream_config.api_url}/api/packages/#{package_name}"

      result = make_request_with_retry(url, upstream_config)

      duration_ms =
        (System.monotonic_time() - start_time)
        |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, _} ->
          HexHub.Telemetry.track_upstream_request("fetch_package", duration_ms, 200)
          result

        {:error, _reason} ->
          HexHub.Telemetry.track_upstream_request("fetch_package", duration_ms, 500, "error")
          result
      end
    end
  end

  @doc """
  Fetch package release tarball from upstream.
  """
  @spec fetch_release_tarball(String.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def fetch_release_tarball(package_name, version) do
    upstream_config = config()

    if not upstream_config.enabled do
      {:error, "Upstream is disabled"}
    else
      start_time = System.monotonic_time()
      url = "#{upstream_config.repo_url}/tarballs/#{package_name}-#{version}.tar"

      # Use raw binary request with retry to preserve tarball integrity for checksum verification
      result = make_raw_binary_request_with_retry(url, upstream_config)

      duration_ms =
        (System.monotonic_time() - start_time)
        |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, _} ->
          HexHub.Telemetry.track_upstream_request("fetch_release_tarball", duration_ms, 200)
          result

        {:error, _reason} ->
          HexHub.Telemetry.track_upstream_request(
            "fetch_release_tarball",
            duration_ms,
            500,
            "error"
          )

          result
      end
    end
  end

  @doc """
  Fetch documentation tarball from upstream.
  """
  @spec fetch_docs_tarball(String.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def fetch_docs_tarball(package_name, version) do
    upstream_config = config()

    if not upstream_config.enabled do
      {:error, "Upstream is disabled"}
    else
      start_time = System.monotonic_time()
      url = "#{upstream_config.repo_url}/docs/#{package_name}-#{version}.tar"

      # Use raw binary request with retry to preserve tarball integrity
      result = make_raw_binary_request_with_retry(url, upstream_config)

      duration_ms =
        (System.monotonic_time() - start_time)
        |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, _} ->
          HexHub.Telemetry.track_upstream_request("fetch_docs_tarball", duration_ms, 200)
          result

        {:error, _reason} ->
          HexHub.Telemetry.track_upstream_request("fetch_docs_tarball", duration_ms, 500, "error")
          result
      end
    end
  end

  @doc """
  Search packages from upstream.

  ## Options

  - `:page` - Page number (default: 1)
  - `:per_page` - Items per page (default: 30)
  - `:sort` - Sort option (default: nil, uses upstream default)
  """
  @spec search_packages(String.t(), keyword()) :: {:ok, [map()], integer()} | {:error, String.t()}
  def search_packages(query, opts \\ []) do
    upstream_config = config()

    if not upstream_config.enabled do
      {:error, "Upstream is disabled"}
    else
      start_time = System.monotonic_time()
      page = Keyword.get(opts, :page, 1)
      per_page = Keyword.get(opts, :per_page, 30)
      sort = Keyword.get(opts, :sort)

      # Build query params
      params =
        [{"search", query}, {"page", to_string(page)}, {"per_page", to_string(per_page)}]
        |> maybe_add_sort(sort)

      query_string = URI.encode_query(params)
      url = "#{upstream_config.api_url}/api/packages?#{query_string}"

      result = make_request_with_retry(url, upstream_config)

      duration_ms =
        (System.monotonic_time() - start_time)
        |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, packages} when is_list(packages) ->
          HexHub.Telemetry.track_upstream_request("search_packages", duration_ms, 200)
          # Hex API returns packages directly, we estimate total from result size
          total =
            if length(packages) < per_page,
              do: (page - 1) * per_page + length(packages),
              else: page * per_page + 1

          {:ok, packages, total}

        {:ok, %{"packages" => packages} = response} when is_list(packages) ->
          HexHub.Telemetry.track_upstream_request("search_packages", duration_ms, 200)
          total = Map.get(response, "total", length(packages))
          {:ok, packages, total}

        {:ok, _} ->
          HexHub.Telemetry.track_upstream_request("search_packages", duration_ms, 200)
          {:ok, [], 0}

        {:error, _reason} ->
          HexHub.Telemetry.track_upstream_request("search_packages", duration_ms, 500, "error")
          {:error, "Failed to search upstream"}
      end
    end
  end

  defp maybe_add_sort(params, nil), do: params
  defp maybe_add_sort(params, :recent_downloads), do: params ++ [{"sort", "recent_downloads"}]
  defp maybe_add_sort(params, :total_downloads), do: params ++ [{"sort", "total_downloads"}]
  defp maybe_add_sort(params, :name), do: params ++ [{"sort", "name"}]
  defp maybe_add_sort(params, :recently_updated), do: params ++ [{"sort", "updated_at"}]
  defp maybe_add_sort(params, :recently_created), do: params ++ [{"sort", "inserted_at"}]
  defp maybe_add_sort(params, _), do: params

  @doc """
  Fetch package releases from upstream.
  """
  @spec fetch_releases(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def fetch_releases(package_name) do
    upstream_config = config()

    if not upstream_config.enabled do
      {:error, "Upstream is disabled"}
    else
      start_time = System.monotonic_time()
      url = "#{upstream_config.api_url}/api/packages/#{package_name}"

      result = make_request_with_retry(url, upstream_config)

      duration_ms =
        (System.monotonic_time() - start_time)
        |> System.convert_time_unit(:native, :millisecond)

      case result do
        {:ok, package_data} when is_map(package_data) ->
          case Map.get(package_data, "releases") do
            releases when is_list(releases) ->
              HexHub.Telemetry.track_upstream_request("fetch_releases", duration_ms, 200)
              {:ok, releases}

            _ ->
              {:error, "Invalid package format: missing releases"}
          end

        {:ok, _} ->
          HexHub.Telemetry.track_upstream_request("fetch_releases", duration_ms, 200)
          result

        {:error, _reason} ->
          HexHub.Telemetry.track_upstream_request("fetch_releases", duration_ms, 500, "error")
          result
      end
    end
  end

  @doc """
  Cache a package from upstream locally.
  """
  @spec cache_package(String.t(), String.t(), binary(), map()) :: :ok | {:error, String.t()}
  def cache_package(package_name, version, tarball, _metadata) do
    # Store the tarball under cached/ directory
    package_key = Storage.generate_package_key(package_name, version, :cached)

    case Storage.upload(package_key, tarball) do
      {:ok, _} ->
        Telemetry.log(:info, :upstream, "Cached package tarball", %{
          package: package_name,
          version: version
        })

        :ok

      {:error, reason} ->
        Telemetry.log(:error, :upstream, "Failed to cache package tarball", %{
          package: package_name,
          version: version,
          reason: reason
        })

        {:error, reason}
    end
  end

  @doc """
  Cache documentation from upstream locally.
  """
  @spec cache_docs(String.t(), String.t(), binary()) :: :ok | {:error, String.t()}
  def cache_docs(package_name, version, docs_tarball) do
    docs_key = Storage.generate_docs_key(package_name, version, :cached)

    case Storage.upload(docs_key, docs_tarball) do
      {:ok, _} ->
        Telemetry.log(:info, :upstream, "Cached docs tarball", %{
          package: package_name,
          version: version
        })

        :ok

      {:error, reason} ->
        Telemetry.log(:error, :upstream, "Failed to cache docs tarball", %{
          package: package_name,
          version: version,
          reason: reason
        })

        {:error, reason}
    end
  end

  ## Private functions

  # Retry wrapper for raw binary requests (tarballs)
  defp make_raw_binary_request_with_retry(url, config, attempt \\ 1) do
    case make_raw_binary_request(url, config) do
      {:ok, _} = result ->
        result

      {:error, reason} when attempt < config.retry_attempts ->
        Telemetry.log(:warning, :upstream, "Upstream tarball request failed, retrying", %{
          attempt: attempt,
          max_attempts: config.retry_attempts,
          reason: reason,
          retry_delay: config.retry_delay
        })

        :timer.sleep(config.retry_delay)
        make_raw_binary_request_with_retry(url, config, attempt + 1)

      {:error, _reason} = error ->
        Telemetry.log(:error, :upstream, "Upstream tarball request failed after max attempts", %{
          attempts: config.retry_attempts
        })

        error
    end
  end

  # Make a raw binary request without any automatic body processing
  # This is critical for tarballs to preserve checksum integrity
  defp make_raw_binary_request(url, config) do
    base_headers = [
      {"user-agent", "HexHub/0.1.0 (Upstream-Mode)"},
      {"accept", "application/octet-stream"}
    ]

    headers =
      case config.api_key do
        nil -> base_headers
        api_key -> [{"authorization", "Bearer #{api_key}"} | base_headers]
      end

    # Disable all automatic response processing to get raw bytes
    req_opts = [
      receive_timeout: config.timeout,
      headers: headers,
      # Disable automatic decompression
      decode_body: false,
      # Disable gzip/deflate handling
      compressed: false,
      # Don't follow redirects automatically for binary data
      redirect: true,
      # Disable retry at Req level (we handle retries ourselves)
      retry: false
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Telemetry.log(:debug, :upstream, "Raw binary response", %{size: byte_size(body)})
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, "Not found upstream"}

      {:ok, %{status: status}} when status in [400, 401, 403] ->
        {:error, "Client error: #{status}"}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, "Server error: #{status}"}

      {:ok, response} ->
        Telemetry.log(:error, :upstream, "Unexpected raw binary response", %{
          status: response.status
        })

        {:error, "Unexpected response status: #{response.status}"}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp make_request_with_retry(url, config, attempt \\ 1) do
    case make_request(url, config) do
      {:ok, _} = result ->
        result

      {:error, reason} when attempt < config.retry_attempts ->
        Telemetry.log(:warning, :upstream, "Upstream request failed, retrying", %{
          attempt: attempt,
          max_attempts: config.retry_attempts,
          reason: reason,
          retry_delay: config.retry_delay
        })

        :timer.sleep(config.retry_delay)
        make_request_with_retry(url, config, attempt + 1)

      {:error, _reason} ->
        Telemetry.log(:error, :upstream, "Upstream request failed after max attempts", %{
          attempts: config.retry_attempts
        })

        {:error, "Request failed after multiple attempts"}
    end
  end

  defp make_request(url, config) do
    # Build headers with optional API key
    base_headers = [
      {"user-agent", "HexHub/0.1.0 (Upstream-Mode)"}
    ]

    headers =
      case config.api_key do
        nil -> base_headers
        api_key -> [{"authorization", "Bearer #{api_key}"} | base_headers]
      end

    req_opts = [
      receive_timeout: config.timeout,
      headers: headers
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Telemetry.log(:debug, :upstream, "Upstream response: binary body", %{
          size: byte_size(body)
        })

        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        Telemetry.log(:debug, :upstream, "Upstream response: map body")
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_list(body) ->
        Telemetry.log(:debug, :upstream, "Upstream response: list body", %{
          item_count: length(body)
        })

        # Check if this is a list of maps (API response like search results)
        # or a list of tuples (tarball contents)
        case body do
          [] ->
            # Empty list - return as is
            {:ok, []}

          [first | _] when is_map(first) ->
            # List of maps - this is a search result or similar API response
            {:ok, body}

          _ ->
            # Handle hex package format - extract the tarball contents
            # Keys may be strings or charlists
            contents_key = "contents.tar.gz"

            case Enum.find(body, fn
                   {key, _} -> key == contents_key or key == String.to_charlist(contents_key)
                   _ -> false
                 end) do
              {_, tarball_data} when is_binary(tarball_data) ->
                Telemetry.log(:debug, :upstream, "Found tarball contents", %{
                  size: byte_size(tarball_data)
                })

                {:ok, tarball_data}

              _ ->
                Telemetry.log(:error, :upstream, "Invalid package format", %{
                  available_keys:
                    Enum.map(body, fn
                      {k, _} -> k
                      other -> inspect(other)
                    end)
                })

                {:error, "Invalid package format: missing contents.tar.gz"}
            end
        end

      {:ok, %{status: 404}} ->
        {:error, "Package not found upstream"}

      {:ok, %{status: status}} when status in [400, 401, 403] ->
        {:error, "Client error: #{status}"}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, "Server error: #{status}"}

      {:ok, response} ->
        Telemetry.log(:error, :upstream, "Unexpected upstream response", %{
          response: inspect(response)
        })

        {:error, "Unexpected response: #{inspect(response)}"}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{reason}"}

      {:error, reason} ->
        {:error, "Request failed: #{reason}"}
    end
  end
end
