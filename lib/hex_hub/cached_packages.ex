defmodule HexHub.CachedPackages do
  @moduledoc """
  Context module for managing cached and local packages with source-aware queries.

  This module provides functions to:
  - Query packages by source (`:local` or `:cached`)
  - List packages with priority/status annotations
  - Get individual packages by source
  - Delete cached packages and clear the cache

  When packages with the same name exist in both sources, local packages
  take priority and cached packages are marked as "shadowed".
  """

  @packages_table :packages
  @package_releases_table :package_releases

  @type source :: :local | :cached
  @type status :: :active | :shadowed

  @type annotated_package :: %{
          name: String.t(),
          repository_name: String.t(),
          meta: map(),
          private: boolean(),
          downloads: integer(),
          inserted_at: integer(),
          updated_at: integer(),
          html_url: String.t() | nil,
          docs_html_url: String.t() | nil,
          source: source(),
          status: status(),
          versions: [String.t()],
          latest_version: String.t() | nil
        }

  @type list_opts :: [
          page: pos_integer(),
          per_page: pos_integer(),
          search: String.t() | nil,
          sort: :name | :downloads | :updated_at,
          sort_dir: :asc | :desc
        ]

  @doc """
  Lists packages filtered by source with pagination, search, and sorting.

  ## Parameters
    - `source` - `:local` or `:cached`
    - `opts` - Keyword list with:
      - `:page` - Page number (default: 1)
      - `:per_page` - Items per page (default: 50, max: 100)
      - `:search` - Package name search term (optional)
      - `:sort` - Sort field: `:name`, `:downloads`, `:updated_at` (default: `:updated_at`)
      - `:sort_dir` - Sort direction: `:asc`, `:desc` (default: `:desc`)

  ## Returns
    - `{:ok, %{packages: [annotated_package()], pagination: map()}}` on success
    - `{:error, reason}` on failure
  """
  @spec list_packages_by_source(source(), list_opts()) ::
          {:ok, %{packages: [annotated_package()], pagination: map()}} | {:error, term()}
  @dialyzer {:nowarn_function, list_packages_by_source: 2}
  def list_packages_by_source(source, opts \\ []) when source in [:local, :cached] do
    page = Keyword.get(opts, :page, 1)
    per_page = min(Keyword.get(opts, :per_page, 50), 100)
    search = Keyword.get(opts, :search)
    sort = Keyword.get(opts, :sort, :updated_at)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)

    case :mnesia.transaction(fn ->
           # Query packages by source
           packages =
             :mnesia.select(@packages_table, [
               {
                 {@packages_table, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9",
                  source},
                 [],
                 [:"$$"]
               }
             ])

           packages
         end) do
      {:atomic, raw_packages} ->
        # Get local package names for shadowing check (only needed for cached source)
        local_names =
          if source == :cached do
            get_local_package_names()
          else
            MapSet.new()
          end

        # Convert to maps and annotate
        packages =
          raw_packages
          |> Enum.map(fn [name, repo, meta, private, downloads, inserted, updated, html, docs] ->
            status =
              if source == :cached and MapSet.member?(local_names, name),
                do: :shadowed,
                else: :active

            versions = get_package_versions(name)

            %{
              name: name,
              repository_name: repo,
              meta: meta,
              private: private,
              downloads: downloads,
              inserted_at: inserted,
              updated_at: updated,
              html_url: html,
              docs_html_url: docs,
              source: source,
              status: status,
              versions: versions,
              latest_version: List.first(versions)
            }
          end)

        # Apply search filter
        packages =
          if search && search != "" do
            search_lower = String.downcase(search)

            Enum.filter(packages, fn pkg ->
              String.contains?(String.downcase(pkg.name), search_lower)
            end)
          else
            packages
          end

        # Sort packages
        packages = sort_packages(packages, sort, sort_dir)

        # Calculate pagination
        total = length(packages)
        total_pages = max(ceil(total / per_page), 1)
        offset = (page - 1) * per_page

        # Paginate
        paginated_packages = packages |> Enum.drop(offset) |> Enum.take(per_page)

        {:ok,
         %{
           packages: paginated_packages,
           pagination: %{
             page: page,
             per_page: per_page,
             total: total,
             total_pages: total_pages
           }
         }}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all packages with priority annotations, combining local and cached sources.

  Local packages are always marked as `:active`.
  Cached packages are marked as `:shadowed` if a local package with the same name exists.

  ## Parameters
    - `opts` - Keyword list with same options as `list_packages_by_source/2`

  ## Returns
    - `{:ok, %{packages: [annotated_package()], pagination: map()}}` on success
    - `{:error, reason}` on failure
  """
  @spec list_packages_with_priority(list_opts()) ::
          {:ok, %{packages: [annotated_package()], pagination: map()}} | {:error, term()}
  def list_packages_with_priority(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = min(Keyword.get(opts, :per_page, 50), 100)
    search = Keyword.get(opts, :search)
    sort = Keyword.get(opts, :sort, :updated_at)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)

    case :mnesia.transaction(fn ->
           # Get all packages
           :mnesia.foldl(
             fn {@packages_table, name, repo, meta, private, downloads, inserted, updated, html,
                 docs, source},
                acc ->
               [
                 {name, repo, meta, private, downloads, inserted, updated, html, docs, source}
                 | acc
               ]
             end,
             [],
             @packages_table
           )
         end) do
      {:atomic, raw_packages} ->
        # Get local package names for shadowing check
        local_names =
          raw_packages
          |> Enum.filter(fn {_, _, _, _, _, _, _, _, _, source} -> source == :local end)
          |> Enum.map(fn {name, _, _, _, _, _, _, _, _, _} -> name end)
          |> MapSet.new()

        # Convert to maps and annotate
        packages =
          raw_packages
          |> Enum.map(fn {name, repo, meta, private, downloads, inserted, updated, html, docs,
                          source} ->
            status =
              if source == :cached and MapSet.member?(local_names, name),
                do: :shadowed,
                else: :active

            versions = get_package_versions(name)

            %{
              name: name,
              repository_name: repo,
              meta: meta,
              private: private,
              downloads: downloads,
              inserted_at: inserted,
              updated_at: updated,
              html_url: html,
              docs_html_url: docs,
              source: source,
              status: status,
              versions: versions,
              latest_version: List.first(versions)
            }
          end)

        # Apply search filter
        packages =
          if search && search != "" do
            search_lower = String.downcase(search)

            Enum.filter(packages, fn pkg ->
              String.contains?(String.downcase(pkg.name), search_lower)
            end)
          else
            packages
          end

        # Sort packages (local packages first when status is used)
        packages = sort_packages(packages, sort, sort_dir)

        # Calculate pagination
        total = length(packages)
        total_pages = max(ceil(total / per_page), 1)
        offset = (page - 1) * per_page

        # Paginate
        paginated_packages = packages |> Enum.drop(offset) |> Enum.take(per_page)

        {:ok,
         %{
           packages: paginated_packages,
           pagination: %{
             page: page,
             per_page: per_page,
             total: total,
             total_pages: total_pages
           }
         }}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a single package by name, filtered by source.

  ## Parameters
    - `name` - Package name
    - `source` - `:local` or `:cached`

  ## Returns
    - `{:ok, annotated_package()}` if found
    - `{:error, :not_found}` if not found or wrong source
    - `{:error, reason}` on failure
  """
  @spec get_package_by_source(String.t(), source()) ::
          {:ok, annotated_package()} | {:error, :not_found | term()}
  def get_package_by_source(name, source) when source in [:local, :cached] do
    case :mnesia.transaction(fn ->
           # Match package by name
           case :mnesia.read(@packages_table, name) do
             [] ->
               nil

             [
               {@packages_table, ^name, repo, meta, private, downloads, inserted, updated, html,
                docs, pkg_source}
             ] ->
               if pkg_source == source do
                 {name, repo, meta, private, downloads, inserted, updated, html, docs, pkg_source}
               else
                 nil
               end
           end
         end) do
      {:atomic, nil} ->
        {:error, :not_found}

      {:atomic, {name, repo, meta, private, downloads, inserted, updated, html, docs, src}} ->
        # Check if shadowed (for cached packages)
        status =
          if src == :cached do
            case :mnesia.dirty_read(@packages_table, name) do
              [{@packages_table, ^name, _, _, _, _, _, _, _, _, :local}] -> :shadowed
              _ -> :active
            end
          else
            :active
          end

        versions = get_package_versions(name)
        releases = get_package_releases(name)

        {:ok,
         %{
           name: name,
           repository_name: repo,
           meta: meta,
           private: private,
           downloads: downloads,
           inserted_at: inserted,
           updated_at: updated,
           html_url: html,
           docs_html_url: docs,
           source: src,
           status: status,
           versions: versions,
           latest_version: List.first(versions),
           releases: releases
         }}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a cached package and all its releases and storage artifacts.

  ## Parameters
    - `name` - Package name to delete

  ## Returns
    - `:ok` on success
    - `{:error, :not_found}` if package doesn't exist or isn't cached
    - `{:error, reason}` on failure
  """
  @spec delete_cached_package(String.t()) :: :ok | {:error, :not_found | term()}
  def delete_cached_package(name) do
    start_time = System.monotonic_time()

    result =
      :mnesia.transaction(fn ->
        # Find the cached package
        case :mnesia.read(@packages_table, name) do
          [] ->
            {:error, :not_found}

          [{@packages_table, ^name, _, _, _, _, _, _, _, _, :cached} = record] ->
            # Delete all releases
            releases =
              :mnesia.match_object(
                {@package_releases_table, name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
              )

            Enum.each(releases, fn release ->
              :mnesia.delete_object(release)
            end)

            # Delete the package
            :mnesia.delete_object(record)

            {:ok, length(releases)}

          [{@packages_table, ^name, _, _, _, _, _, _, _, _, _source}] ->
            # Not a cached package
            {:error, :not_found}
        end
      end)

    case result do
      {:atomic, {:ok, release_count}} ->
        # Delete storage artifacts (tarballs)
        delete_package_storage(name)

        # Emit telemetry
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:hex_hub, :admin, :cached_package, :deleted],
          %{duration: duration},
          %{package_name: name, release_count: release_count}
        )

        :ok

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears all cached packages from the system.

  ## Returns
    - `{:ok, count}` with number of deleted packages on success
    - `{:error, reason}` on failure
  """
  @spec clear_all_cached_packages() :: {:ok, non_neg_integer()} | {:error, term()}
  def clear_all_cached_packages do
    start_time = System.monotonic_time()

    result =
      :mnesia.transaction(fn ->
        # Find all cached packages
        cached_packages =
          :mnesia.select(@packages_table, [
            {
              {@packages_table, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :cached},
              [],
              [:"$1"]
            }
          ])

        # Delete each package and its releases
        Enum.each(cached_packages, fn name ->
          # Delete releases
          releases =
            :mnesia.match_object(
              {@package_releases_table, name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
            )

          Enum.each(releases, fn release ->
            :mnesia.delete_object(release)
          end)

          # Delete package
          :mnesia.delete({@packages_table, name})
        end)

        length(cached_packages)
      end)

    case result do
      {:atomic, count} ->
        # Delete all cached storage artifacts
        delete_all_cached_storage()

        # Emit telemetry
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:hex_hub, :admin, :cache, :cleared],
          %{duration: duration},
          %{count: count}
        )

        {:ok, count}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a local package exists with the given name.

  ## Parameters
    - `name` - Package name to check

  ## Returns
    - `true` if local package exists
    - `false` otherwise
  """
  @spec has_local_counterpart?(String.t()) :: boolean()
  def has_local_counterpart?(name) do
    case :mnesia.dirty_read(@packages_table, name) do
      [{@packages_table, ^name, _, _, _, _, _, _, _, _, :local}] -> true
      _ -> false
    end
  end

  @doc """
  Checks if a cached package exists with the given name.

  ## Parameters
    - `name` - Package name to check

  ## Returns
    - `true` if cached package exists
    - `false` otherwise
  """
  @spec has_cached_counterpart?(String.t()) :: boolean()
  def has_cached_counterpart?(name) do
    case :mnesia.dirty_read(@packages_table, name) do
      [{@packages_table, ^name, _, _, _, _, _, _, _, _, :cached}] -> true
      _ -> false
    end
  end

  @doc """
  Returns package statistics for admin dashboard.

  ## Returns
    - Map with local_count, cached_count, shadowed_count
  """
  @spec get_package_stats() :: %{
          local_count: non_neg_integer(),
          cached_count: non_neg_integer(),
          shadowed_count: non_neg_integer()
        }
  def get_package_stats do
    case :mnesia.transaction(fn ->
           packages =
             :mnesia.foldl(
               fn {@packages_table, name, _, _, _, _, _, _, _, _, source}, acc ->
                 [{name, source} | acc]
               end,
               [],
               @packages_table
             )

           packages
         end) do
      {:atomic, packages} ->
        local_names =
          packages
          |> Enum.filter(fn {_, source} -> source == :local end)
          |> Enum.map(fn {name, _} -> name end)
          |> MapSet.new()

        local_count = MapSet.size(local_names)

        cached =
          packages
          |> Enum.filter(fn {_, source} -> source == :cached end)

        cached_count = length(cached)

        shadowed_count =
          cached
          |> Enum.count(fn {name, _} -> MapSet.member?(local_names, name) end)

        %{
          local_count: local_count,
          cached_count: cached_count,
          shadowed_count: shadowed_count
        }

      {:aborted, _reason} ->
        %{local_count: 0, cached_count: 0, shadowed_count: 0}
    end
  end

  # Private functions

  defp get_local_package_names do
    case :mnesia.transaction(fn ->
           :mnesia.select(@packages_table, [
             {
               {@packages_table, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :local},
               [],
               [:"$1"]
             }
           ])
         end) do
      {:atomic, names} -> MapSet.new(names)
      {:aborted, _} -> MapSet.new()
    end
  end

  defp get_package_versions(name) do
    @package_releases_table
    |> :mnesia.dirty_match_object(
      {@package_releases_table, name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    |> Enum.map(fn {_, _, version, _, _, _, _, _, _, _, _, _, _, _} -> version end)
    |> Enum.sort(&version_compare/2)
  end

  defp get_package_releases(name) do
    @package_releases_table
    |> :mnesia.dirty_match_object(
      {@package_releases_table, name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    |> Enum.map(fn {_, pkg_name, version, has_docs, meta, requirements, retired, downloads,
                    inserted, updated, url, pkg_url, html_url, docs_url} ->
      %{
        package_name: pkg_name,
        version: version,
        has_docs: has_docs,
        meta: meta,
        requirements: requirements,
        retired: retired,
        downloads: downloads,
        inserted_at: inserted,
        updated_at: updated,
        url: url,
        package_url: pkg_url,
        html_url: html_url,
        docs_html_url: docs_url
      }
    end)
    |> Enum.sort_by(& &1.version, &version_compare/2)
  end

  defp version_compare(v1, v2) do
    case {Version.parse(v1), Version.parse(v2)} do
      {{:ok, parsed1}, {:ok, parsed2}} -> Version.compare(parsed1, parsed2) != :lt
      _ -> v1 >= v2
    end
  end

  defp sort_packages(packages, sort, sort_dir) do
    sorter =
      case sort do
        :name -> & &1.name
        :downloads -> & &1.downloads
        :updated_at -> & &1.updated_at
        _ -> & &1.updated_at
      end

    sorted = Enum.sort_by(packages, sorter)

    if sort_dir == :desc do
      Enum.reverse(sorted)
    else
      sorted
    end
  end

  defp delete_package_storage(name) do
    # Delete package and docs tarballs from cached storage
    versions = get_package_versions(name)

    Enum.each(versions, fn version ->
      package_key = HexHub.Storage.generate_package_key(name, version, :cached)
      docs_key = HexHub.Storage.generate_docs_key(name, version, :cached)
      HexHub.Storage.delete(package_key)
      HexHub.Storage.delete(docs_key)
    end)
  end

  defp delete_all_cached_storage do
    # Get all cached package names and delete their storage
    case :mnesia.transaction(fn ->
           :mnesia.select(@packages_table, [
             {
               {@packages_table, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :cached},
               [],
               [:"$1"]
             }
           ])
         end) do
      {:atomic, names} ->
        Enum.each(names, &delete_package_storage/1)

      _ ->
        :ok
    end
  end

  @doc """
  Refreshes all cached packages by re-fetching metadata from upstream.

  For each cached package:
  1. Fetches latest package metadata from upstream
  2. Fetches the list of releases from upstream
  3. Downloads and caches any new release tarballs not yet stored locally
  4. Updates the package and release records in Mnesia

  Returns `{:ok, %{refreshed: count, new_releases: count, errors: [...]}}`.
  """
  @spec refresh_all_cached_packages() :: {:ok, map()} | {:error, term()}
  def refresh_all_cached_packages do
    start_time = System.monotonic_time()

    if not HexHub.Upstream.enabled?() do
      {:error, "Upstream is disabled"}
    else
      # Get all cached package names
      cached_names = list_cached_package_names()

      results =
        Enum.map(cached_names, fn name ->
          case refresh_cached_package(name) do
            {:ok, result} -> {:ok, name, result}
            {:error, reason} -> {:error, name, reason}
          end
        end)

      refreshed = Enum.count(results, fn {status, _, _} -> status == :ok end)

      new_releases =
        results
        |> Enum.filter(fn {status, _, _} -> status == :ok end)
        |> Enum.map(fn {:ok, _, result} -> result.new_releases end)
        |> Enum.sum()

      errors =
        results
        |> Enum.filter(fn {status, _, _} -> status == :error end)
        |> Enum.map(fn {:error, name, reason} -> %{package: name, reason: reason} end)

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:hex_hub, :admin, :cache, :refreshed],
        %{duration: duration},
        %{refreshed: refreshed, new_releases: new_releases, errors: length(errors)}
      )

      {:ok, %{refreshed: refreshed, new_releases: new_releases, errors: errors}}
    end
  end

  @doc """
  Refreshes a single cached package by re-fetching from upstream.

  Returns `{:ok, %{new_releases: count}}` on success.
  """
  @spec refresh_cached_package(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh_cached_package(name) do
    if not HexHub.Upstream.enabled?() do
      {:error, "Upstream is disabled"}
    else
      with {:ok, upstream_pkg} <- HexHub.Upstream.fetch_package(name),
           {:ok, upstream_releases} <- HexHub.Upstream.fetch_releases(name) do
        # Update package metadata
        update_cached_package_metadata(name, upstream_pkg)

        # Find new releases not yet cached locally
        local_versions = get_package_versions(name) |> MapSet.new()

        new_releases =
          upstream_releases
          |> Enum.filter(fn r -> not MapSet.member?(local_versions, r["version"]) end)

        # Cache new release tarballs
        cached_count =
          Enum.count(new_releases, fn release ->
            version = release["version"]

            case HexHub.Upstream.fetch_release_tarball(name, version) do
              {:ok, tarball} ->
                case HexHub.Upstream.cache_package(name, version, tarball, %{}) do
                  :ok ->
                    create_cached_release(name, release)
                    true

                  {:error, _} ->
                    false
                end

              {:error, _} ->
                false
            end
          end)

        {:ok, %{new_releases: cached_count}}
      end
    end
  end

  @doc """
  Refreshes the registry cache by re-fetching /names, /versions, and
  /packages/:name for all cached packages from upstream.

  This ensures the hex client can resolve dependencies even when
  upstream is temporarily unavailable.
  """
  @spec refresh_registry_cache() :: {:ok, map()} | {:error, term()}
  def refresh_registry_cache do
    if not HexHub.Upstream.enabled?() do
      {:error, "Upstream is disabled"}
    else
      config = HexHub.Upstream.config()
      results = %{names: false, versions: false, packages: 0, errors: []}

      # Refresh /names
      results = refresh_registry_endpoint(config, "/names", results, :names)

      # Refresh /versions
      results = refresh_registry_endpoint(config, "/versions", results, :versions)

      # Refresh /packages/:name for all cached packages
      cached_names = list_cached_package_names()

      results =
        Enum.reduce(cached_names, results, fn name, acc ->
          case fetch_and_cache_registry(config, "/packages/#{name}") do
            :ok ->
              Map.update!(acc, :packages, &(&1 + 1))

            {:error, reason} ->
              Map.update!(acc, :errors, &[%{path: "/packages/#{name}", reason: reason} | &1])
          end
        end)

      {:ok, results}
    end
  end

  defp refresh_registry_endpoint(config, path, results, key) do
    case fetch_and_cache_registry(config, path) do
      :ok ->
        Map.put(results, key, true)

      {:error, reason} ->
        results
        |> Map.put(key, false)
        |> Map.update!(:errors, &[%{path: path, reason: reason} | &1])
    end
  end

  defp fetch_and_cache_registry(config, path) do
    url = "#{config.repo_url}#{path}"

    headers = [
      {"user-agent", "HexHub/#{Application.spec(:hex_hub, :vsn)} (Registry-Refresh)"},
      {"accept", "application/octet-stream"}
    ]

    req_opts = [
      receive_timeout: config.timeout,
      headers: headers,
      decode_body: false,
      compressed: false
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body, headers: resp_headers}} ->
        relevant_headers =
          resp_headers
          |> Enum.filter(fn {name, _} ->
            String.downcase(name) in [
              "content-type",
              "content-encoding",
              "etag",
              "cache-control",
              "last-modified"
            ]
          end)
          |> Enum.map(fn {name, value} -> {String.downcase(name), value} end)

        record =
          {:registry_cache, path, body, relevant_headers, System.system_time(:second)}

        case :mnesia.transaction(fn -> :mnesia.write(record) end) do
          {:atomic, :ok} -> :ok
          {:aborted, reason} -> {:error, "Cache write failed: #{inspect(reason)}"}
        end

      {:ok, %{status: status}} ->
        {:error, "Upstream returned status #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp list_cached_package_names do
    case :mnesia.transaction(fn ->
           :mnesia.select(@packages_table, [
             {
               {@packages_table, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :cached},
               [],
               [:"$1"]
             }
           ])
         end) do
      {:atomic, names} -> names
      _ -> []
    end
  end

  defp update_cached_package_metadata(name, upstream_pkg) do
    meta = %{
      "description" => get_in(upstream_pkg, ["meta", "description"]),
      "licenses" => get_in(upstream_pkg, ["meta", "licenses"]) || [],
      "links" => get_in(upstream_pkg, ["meta", "links"]) || %{},
      "maintainers" => get_in(upstream_pkg, ["meta", "maintainers"]) || [],
      "extra" => get_in(upstream_pkg, ["meta", "extra"]) || %{}
    }

    repository_name = upstream_pkg["repository"] || "hexpm"
    now = DateTime.utc_now()

    case :mnesia.dirty_read(@packages_table, name) do
      [
        {@packages_table, ^name, _repo, _meta, private, downloads, inserted_at, _updated_at,
         html_url, docs_html_url, :cached}
      ] ->
        updated =
          {@packages_table, name, repository_name, meta, private, downloads, inserted_at, now,
           html_url, docs_html_url, :cached}

        case :mnesia.transaction(fn -> :mnesia.write(updated) end) do
          {:atomic, :ok} -> :ok
          {:aborted, reason} -> {:error, inspect(reason)}
        end

      _ ->
        # Package not found or not cached, create it
        HexHub.Packages.create_package(name, repository_name, meta, false, :cached)
    end
  end

  defp create_cached_release(name, release_info) do
    now = DateTime.utc_now()
    version = release_info["version"]

    meta = %{
      "app" => get_in(release_info, ["meta", "app"]),
      "build_tools" => get_in(release_info, ["meta", "build_tools"]) || [],
      "elixir" => get_in(release_info, ["meta", "elixir"])
    }

    requirements =
      case release_info["requirements"] do
        reqs when is_map(reqs) -> reqs
        _ -> %{}
      end

    release =
      {@package_releases_table, name, version, false, meta, requirements, false, 0, now, now,
       "/packages/#{name}/releases/#{version}", "/packages/#{name}/releases/#{version}/package",
       "/packages/#{name}/releases/#{version}", "/packages/#{name}/releases/#{version}/docs"}

    case :mnesia.transaction(fn -> :mnesia.write(release) end) do
      {:atomic, :ok} -> :ok
      {:aborted, _reason} -> :error
    end
  end
end
