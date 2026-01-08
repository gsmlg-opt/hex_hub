defmodule HexHub.Packages do
  @moduledoc """
  Package management functions with Mnesia storage and file handling.
  Supports upstream fetching for packages not available locally.
  """

  alias HexHub.{Storage, Telemetry, Upstream}

  @type package :: %{
          name: String.t(),
          repository_name: String.t(),
          meta: map(),
          private: boolean(),
          downloads: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t(),
          html_url: String.t(),
          docs_html_url: String.t(),
          source: :local | :cached
        }

  @type release :: %{
          package_name: String.t(),
          version: String.t(),
          has_docs: boolean(),
          meta: map(),
          requirements: map(),
          retired: boolean(),
          downloads: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t(),
          url: String.t(),
          package_url: String.t(),
          html_url: String.t(),
          docs_html_url: String.t()
        }

  @packages_table :packages
  @releases_table :package_releases
  @owners_table :package_owners

  @doc """
  Reset test data - mainly for testing purposes.
  """
  def reset_test_store do
    :mnesia.clear_table(@packages_table)
    :mnesia.clear_table(@releases_table)
    :mnesia.clear_table(@owners_table)
    :ok
  end

  @doc """
  Create a new package.
  """
  @spec create_package(String.t(), String.t(), map(), boolean(), atom()) ::
          {:ok, package()} | {:error, String.t()}
  def create_package(name, repository_name, meta, private \\ false, source \\ :local) do
    start_time = System.monotonic_time()

    with :ok <- validate_package_name(name) do
      now = DateTime.utc_now()

      package = {
        @packages_table,
        name,
        repository_name,
        meta,
        private,
        # downloads
        0,
        now,
        now,
        "/packages/#{name}",
        "/packages/#{name}/docs",
        source
      }

      case :mnesia.transaction(fn ->
             :mnesia.write(package)
           end) do
        {:atomic, :ok} ->
          package_map = package_to_map(package)

          duration_ms =
            (System.monotonic_time() - start_time)
            |> System.convert_time_unit(:native, :millisecond)

          HexHub.Telemetry.track_mnesia_operation("create_package", duration_ms)
          HexHub.Telemetry.track_package_published(repository_name)

          HexHub.Audit.log_event("package_created", "package", name, %{
            repository: repository_name,
            private: private
          })

          {:ok, package_map}

        {:aborted, reason} ->
          duration_ms =
            (System.monotonic_time() - start_time)
            |> System.convert_time_unit(:native, :millisecond)

          HexHub.Telemetry.track_mnesia_operation("create_package", duration_ms)
          {:error, "Failed to create package: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get package by name. Falls back to upstream if not found locally.
  """
  @spec get_package(String.t()) :: {:ok, package()} | {:error, :not_found}
  def get_package(name) do
    # Use dirty_read for read-only single-key lookup (no transaction needed)
    case :mnesia.dirty_read(@packages_table, name) do
      [
        {@packages_table, name, repository_name, meta, private, downloads, inserted_at,
         updated_at, html_url, docs_html_url, source}
      ] ->
        {:ok,
         package_to_map(
           {@packages_table, name, repository_name, meta, private, downloads, inserted_at,
            updated_at, html_url, docs_html_url, source}
         )}

      [] ->
        # Try upstream fetching
        fetch_package_from_upstream(name)
    end
  rescue
    # Handle Mnesia errors gracefully
    _error ->
      {:error, :not_found}
  end

  @doc """
  List all packages with optional search, sorting, letter filtering, and pagination.

  Searches local packages first. If no local results are found and a search term
  is provided, falls back to searching upstream (hex.pm).

  ## Options

  - `:search` - Search term for name/description (case-insensitive)
  - `:sort` - Sort option (default: `:recent_downloads`)
    - `:recent_downloads` - By recent download count (descending)
    - `:total_downloads` - By all-time download count (descending)
    - `:name` - Alphabetically A-Z
    - `:recently_updated` - By last update timestamp (descending)
    - `:recently_created` - By creation timestamp (descending)
  - `:letter` - Filter by first letter of package name (A-Z)
  - `:page` - Page number (default: 1)
  - `:per_page` - Items per page (default: 30)
  - `:upstream_fallback` - Whether to fall back to upstream search (default: true)
  """
  @spec list_packages(keyword()) :: {:ok, [package()], integer()} | {:error, String.t()}
  def list_packages(opts \\ []) do
    start_time = System.monotonic_time()
    search_term = Keyword.get(opts, :search)
    sort = Keyword.get(opts, :sort, :recent_downloads)
    letter = Keyword.get(opts, :letter)
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 30)
    upstream_fallback = Keyword.get(opts, :upstream_fallback, true)

    offset = (page - 1) * per_page

    case :mnesia.transaction(fn ->
           packages =
             :mnesia.foldl(
               fn {_, name, repository_name, meta, private, downloads, inserted_at, updated_at,
                   html_url, docs_html_url, source},
                  acc ->
                 package =
                   package_to_map(
                     {@packages_table, name, repository_name, meta, private, downloads,
                      inserted_at, updated_at, html_url, docs_html_url, source}
                   )

                 # Apply filters
                 if matches_search?(package, search_term) and starts_with_letter?(package, letter) do
                   [package | acc]
                 else
                   acc
                 end
               end,
               [],
               @packages_table
             )

           # Apply sorting
           sorted_packages = apply_sort(packages, sort)

           total_count = length(sorted_packages)

           paginated_packages =
             sorted_packages
             |> Enum.drop(offset)
             |> Enum.take(per_page)

           {paginated_packages, total_count}
         end) do
      {:atomic, {[], 0}}
      when is_binary(search_term) and search_term != "" and upstream_fallback ->
        # No local results found, try upstream search
        search_packages_upstream(search_term, opts, start_time)

      {:atomic, {packages, total}} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        :telemetry.execute(
          [:hex_hub, :packages, :browse],
          %{duration: duration_ms},
          %{
            page: page,
            sort: sort,
            search: search_term,
            letter: letter,
            results: total,
            source: :local
          }
        )

        {:ok, packages, total}

      {:aborted, reason} ->
        {:error, "Failed to list packages: #{inspect(reason)}"}
    end
  end

  # Search packages from upstream and convert to local format
  defp search_packages_upstream(search_term, opts, start_time) do
    sort = Keyword.get(opts, :sort, :recent_downloads)
    letter = Keyword.get(opts, :letter)
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 30)

    case Upstream.search_packages(search_term, page: page, per_page: per_page, sort: sort) do
      {:ok, upstream_packages, total} ->
        # Convert upstream packages to local format
        packages =
          upstream_packages
          |> Enum.map(&convert_upstream_package/1)
          |> Enum.filter(&starts_with_letter?(&1, letter))

        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        :telemetry.execute(
          [:hex_hub, :packages, :browse],
          %{duration: duration_ms},
          %{
            page: page,
            sort: sort,
            search: search_term,
            letter: letter,
            results: total,
            source: :upstream
          }
        )

        Telemetry.log(:info, :package, "Searched packages from upstream", %{
          search: search_term,
          results: length(packages),
          total: total
        })

        {:ok, packages, total}

      {:error, _reason} ->
        # Upstream search failed, return empty results
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        :telemetry.execute(
          [:hex_hub, :packages, :browse],
          %{duration: duration_ms},
          %{
            page: page,
            sort: sort,
            search: search_term,
            letter: letter,
            results: 0,
            source: :upstream_failed
          }
        )

        {:ok, [], 0}
    end
  end

  # Convert an upstream package map to local package format
  defp convert_upstream_package(upstream_pkg) do
    now = DateTime.utc_now()

    # Parse dates if available
    inserted_at = parse_upstream_datetime(upstream_pkg["inserted_at"]) || now
    updated_at = parse_upstream_datetime(upstream_pkg["updated_at"]) || now

    %{
      name: upstream_pkg["name"],
      repository_name: upstream_pkg["repository"] || "hexpm",
      meta: upstream_pkg["meta"] || %{},
      private: false,
      downloads: (upstream_pkg["downloads"] && upstream_pkg["downloads"]["all"]) || 0,
      inserted_at: inserted_at,
      updated_at: updated_at,
      html_url: upstream_pkg["html_url"] || "/packages/#{upstream_pkg["name"]}",
      docs_html_url: upstream_pkg["docs_html_url"] || "/packages/#{upstream_pkg["name"]}/docs",
      source: :cached
    }
  end

  defp parse_upstream_datetime(nil), do: nil

  defp parse_upstream_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_upstream_datetime(_), do: nil

  # Apply sorting to a list of packages.
  defp apply_sort(packages, sort) do
    case sort do
      :recent_downloads ->
        Enum.sort_by(packages, &{-&1.downloads, &1.name})

      :total_downloads ->
        Enum.sort_by(packages, &{-&1.downloads, &1.name})

      :name ->
        Enum.sort_by(packages, & &1.name)

      :recently_updated ->
        Enum.sort_by(packages, & &1.updated_at, {:desc, DateTime})

      :recently_created ->
        Enum.sort_by(packages, & &1.inserted_at, {:desc, DateTime})

      _ ->
        Enum.sort_by(packages, &{-&1.downloads, &1.name})
    end
  end

  # Check if package name starts with the given letter.
  defp starts_with_letter?(_package, nil), do: true
  defp starts_with_letter?(_package, ""), do: true

  defp starts_with_letter?(package, letter) when is_binary(letter) do
    letter = String.upcase(letter)
    first_letter = package.name |> String.first() |> String.upcase()
    first_letter == letter
  end

  @doc """
  List most downloaded packages.
  """
  @spec list_most_downloaded(integer()) :: [package()]
  def list_most_downloaded(limit \\ 5) do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn {_, name, repository_name, meta, private, downloads, inserted_at, updated_at,
                 html_url, docs_html_url, source},
                acc ->
               package =
                 package_to_map(
                   {@packages_table, name, repository_name, meta, private, downloads, inserted_at,
                    updated_at, html_url, docs_html_url, source}
                 )

               [package | acc]
             end,
             [],
             @packages_table
           )
         end) do
      {:atomic, packages} ->
        packages
        |> Enum.sort_by(& &1.downloads, :desc)
        |> Enum.take(limit)

      {:aborted, _reason} ->
        []
    end
  end

  @doc """
  List recently updated packages (packages with most recent releases).
  """
  @spec list_recently_updated(integer()) :: [package()]
  def list_recently_updated(limit \\ 5) do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn {_, name, repository_name, meta, private, downloads, inserted_at, updated_at,
                 html_url, docs_html_url, source},
                acc ->
               package =
                 package_to_map(
                   {@packages_table, name, repository_name, meta, private, downloads, inserted_at,
                    updated_at, html_url, docs_html_url, source}
                 )

               [package | acc]
             end,
             [],
             @packages_table
           )
         end) do
      {:atomic, packages} ->
        packages
        |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
        |> Enum.take(limit)

      {:aborted, _reason} ->
        []
    end
  end

  @doc """
  List newest packages by creation date.
  """
  @spec list_new_packages(integer()) :: [package()]
  def list_new_packages(limit \\ 5) do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn {_, name, repository_name, meta, private, downloads, inserted_at, updated_at,
                 html_url, docs_html_url, source},
                acc ->
               package =
                 package_to_map(
                   {@packages_table, name, repository_name, meta, private, downloads, inserted_at,
                    updated_at, html_url, docs_html_url, source}
                 )

               [package | acc]
             end,
             [],
             @packages_table
           )
         end) do
      {:atomic, packages} ->
        packages
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.take(limit)

      {:aborted, _reason} ->
        []
    end
  end

  @doc """
  Search packages by name or description.
  """
  @spec search_packages(String.t(), keyword()) ::
          {:ok, [package()], integer()} | {:error, String.t()}
  def search_packages(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    list_packages(search: query, page: page, per_page: per_page)
  end

  defp matches_search?(_package, nil), do: true
  defp matches_search?(_package, ""), do: true

  defp matches_search?(package, search_term) do
    search_term = String.downcase(search_term)
    name_match = package.name |> String.downcase() |> String.contains?(search_term)

    description_match =
      case package.meta["description"] do
        nil -> false
        description -> description |> String.downcase() |> String.contains?(search_term)
      end

    name_match or description_match
  end

  @doc """
  Create a new package release with file upload.
  """
  @spec create_release(String.t(), String.t(), map(), map(), binary()) ::
          {:ok, release()} | {:error, String.t()}
  def create_release(package_name, version, meta, requirements, tarball) do
    with :ok <- validate_version(version),
         {:ok, _package} <- get_package(package_name) do
      # Upload package file
      package_key = Storage.generate_package_key(package_name, version)

      case Storage.upload(package_key, tarball) do
        {:ok, _} ->
          now = DateTime.utc_now()

          release = {
            @releases_table,
            package_name,
            version,
            # has_docs
            false,
            meta,
            requirements,
            # retired
            false,
            # downloads
            0,
            now,
            now,
            "/packages/#{package_name}/releases/#{version}",
            "/packages/#{package_name}/releases/#{version}/package",
            "/packages/#{package_name}/releases/#{version}",
            "/packages/#{package_name}/releases/#{version}/docs"
          }

          case :mnesia.transaction(fn ->
                 :mnesia.write(release)
               end) do
            {:atomic, :ok} ->
              release_map = release_to_map(release)

              HexHub.Audit.log_event(
                "release_created",
                "package_release",
                "#{package_name}-#{version}",
                %{
                  package_name: package_name,
                  version: version,
                  meta: meta
                }
              )

              {:ok, release_map}

            {:aborted, reason} ->
              # Rollback file upload
              Storage.delete(package_key)
              {:error, "Failed to create release: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to upload package: #{reason}"}
      end
    else
      {:error, :not_found} -> {:error, "Package not found"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get package release. Falls back to upstream if not found locally.
  """
  @spec get_release(String.t(), String.t()) :: {:ok, release()} | {:error, :not_found}
  def get_release(package_name, version) do
    case :mnesia.transaction(fn ->
           # Match all releases for this package and version
           :mnesia.match_object(
             {@releases_table, package_name, version, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
           )
         end) do
      {:atomic, []} ->
        # Try upstream fetching
        fetch_release_from_upstream(package_name, version)

      {:atomic, releases} when is_list(releases) ->
        # For :bag type, take the most recent one (last written)
        release =
          Enum.max_by(releases, fn release_tuple ->
            case release_tuple do
              {@releases_table, _, _, _, _, _, _, _, _, updated_at, _, _, _, _} -> updated_at
              # fallback
              _ -> DateTime.utc_now()
            end
          end)

        {:ok, release_to_map(release)}

      {:aborted, _reason} ->
        {:error, :not_found}
    end
  end

  @doc """
  List releases for a package.
  """
  @spec list_releases(String.t()) :: {:ok, [release()]}
  def list_releases(package_name) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object(
             {@releases_table, package_name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
           )
         end) do
      {:atomic, releases} ->
        {:ok, Enum.map(releases, &release_to_map/1)}

      {:aborted, reason} ->
        {:error, "Failed to list releases: #{inspect(reason)}"}
    end
  end

  @doc """
  Upload documentation for a release.
  """
  @spec upload_docs(String.t(), String.t(), binary()) :: {:ok, release()} | {:error, String.t()}
  def upload_docs(package_name, version, docs_tarball) do
    docs_key = Storage.generate_docs_key(package_name, version)

    with {:ok, _release} <- get_release(package_name, version),
         {:ok, _} <- Storage.upload(docs_key, docs_tarball),
         {:ok, _} <- update_release_docs_flag(package_name, version, true) do
      get_release(package_name, version)
    else
      {:error, :not_found} ->
        {:error, "Release not found"}

      {:error, reason} = error ->
        # Clean up uploaded docs if database update failed
        cleanup_docs_on_error(docs_key, reason)
        error
    end
  end

  defp cleanup_docs_on_error(docs_key, reason) do
    if String.contains?(to_string(reason), ["update", "transaction", "mnesia"]) do
      Storage.delete(docs_key)
    end
  end

  @doc """
  Download package tarball.
  """
  @spec download_package(String.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def download_package(package_name, version) do
    package_key = Storage.generate_package_key(package_name, version)
    Storage.download(package_key)
  end

  @doc """
  Download documentation tarball.
  """
  @spec download_docs(String.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def download_docs(package_name, version) do
    docs_key = Storage.generate_docs_key(package_name, version)
    Storage.download(docs_key)
  end

  @doc """
  Delete documentation for a release.
  """
  @spec delete_docs(String.t(), String.t()) :: {:ok, release()} | {:error, String.t()}
  def delete_docs(package_name, version) do
    docs_key = Storage.generate_docs_key(package_name, version)

    with :ok <- Storage.delete(docs_key),
         {:ok, _} <- update_release_docs_flag(package_name, version, false) do
      get_release(package_name, version)
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "Failed to delete docs: #{inspect(reason)}"}
    end
  end

  defp update_release_docs_flag(package_name, version, has_docs) do
    case :mnesia.transaction(fn ->
           do_update_release_docs_flag(package_name, version, has_docs)
         end) do
      {:atomic, {:ok, _} = result} -> result
      {:atomic, {:error, _} = error} -> error
      {:aborted, reason} -> {:error, "Transaction failed: #{inspect(reason)}"}
    end
  end

  defp do_update_release_docs_flag(package_name, version, has_docs) do
    releases =
      :mnesia.match_object(
        {@releases_table, package_name, version, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )

    case releases do
      [] -> {:error, "Release not found"}
      _ -> update_all_release_docs_flags(releases, has_docs)
    end
  end

  defp update_all_release_docs_flags(releases, has_docs) do
    Enum.each(releases, fn release_tuple ->
      update_single_release_docs_flag(release_tuple, has_docs)
    end)

    {:ok, :updated}
  end

  defp update_single_release_docs_flag(release_tuple, has_docs) do
    {@releases_table, pkg_name, ver, _old_has_docs, meta, requirements, retired, downloads,
     inserted_at, _updated_at, url, package_url, html_url, docs_html_url} = release_tuple

    :mnesia.delete_object(release_tuple)

    updated_release = {
      @releases_table,
      pkg_name,
      ver,
      has_docs,
      meta,
      requirements,
      retired,
      downloads,
      inserted_at,
      DateTime.utc_now(),
      url,
      package_url,
      html_url,
      docs_html_url
    }

    :mnesia.write(updated_release)
  end

  @doc """
  Add an owner to a package.
  """
  @spec add_package_owner(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def add_package_owner(package_name, username, level \\ "full") do
    now = DateTime.utc_now()
    owner = {:package_owners, package_name, username, level, now}

    case :mnesia.transaction(fn ->
           :mnesia.write(owner)
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, "Failed to add owner: #{inspect(reason)}"}
    end
  end

  @doc """
  Get package owners.
  """
  @spec get_package_owners(String.t()) :: {:ok, list()} | {:error, String.t()}
  def get_package_owners(package_name) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object({:package_owners, package_name, :_, :_, :_})
         end) do
      {:atomic, owners} when is_list(owners) ->
        owner_list =
          Enum.map(owners, fn {:package_owners, _pkg, username, level, inserted_at} ->
            %{
              username: username,
              level: level,
              inserted_at: inserted_at
            }
          end)

        {:ok, owner_list}

      {:atomic, []} ->
        {:ok, []}

      {:aborted, reason} ->
        {:error, "Failed to get owners: #{inspect(reason)}"}
    end
  end

  @doc """
  Retire a package release.
  """
  @spec retire_release(String.t(), String.t()) :: {:ok, release()} | {:error, String.t()}
  def retire_release(package_name, version) do
    update_release_retirement_status(package_name, version, true)
  end

  @doc """
  Unretire a package release.
  """
  @spec unretire_release(String.t(), String.t()) :: {:ok, release()} | {:error, String.t()}
  def unretire_release(package_name, version) do
    update_release_retirement_status(package_name, version, false)
  end

  defp update_release_retirement_status(package_name, version, retired) do
    with {:ok, _release} <- get_release(package_name, version),
         {:ok, release_tuple} <- update_retirement_in_transaction(package_name, version, retired) do
      {:ok, release_to_map(release_tuple)}
    else
      {:error, :not_found} -> {:error, "Release not found"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_retirement_in_transaction(package_name, version, retired) do
    case :mnesia.transaction(fn ->
           do_update_retirement_status(package_name, version, retired)
         end) do
      {:atomic, {:ok, _} = result} -> result
      {:atomic, {:error, _} = error} -> error
      {:aborted, reason} -> {:error, "Failed to update retirement status: #{inspect(reason)}"}
    end
  end

  defp do_update_retirement_status(package_name, version, retired) do
    releases =
      :mnesia.match_object(
        {@releases_table, package_name, version, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )

    case releases do
      [] -> {:error, "Release not found"}
      _ -> update_all_releases_retirement(releases, retired)
    end
  end

  defp update_all_releases_retirement(releases, retired) do
    Enum.each(releases, fn release_tuple ->
      update_single_release_retirement(release_tuple, retired)
    end)

    {:ok, hd(releases)}
  end

  defp update_single_release_retirement(release_tuple, retired) do
    {_, pkg_name, ver, has_docs, meta, requirements, _old_retired, downloads, inserted_at,
     _updated_at, url, package_url, html_url, docs_html_url} = release_tuple

    updated_release = {
      @releases_table,
      pkg_name,
      ver,
      has_docs,
      meta,
      requirements,
      retired,
      downloads,
      inserted_at,
      DateTime.utc_now(),
      url,
      package_url,
      html_url,
      docs_html_url
    }

    :mnesia.write(updated_release)
  end

  ## Helper functions

  defp package_to_map(
         {@packages_table, name, repository_name, meta, private, downloads, inserted_at,
          updated_at, html_url, docs_html_url, source}
       ) do
    %{
      name: name,
      repository_name: repository_name,
      meta: meta,
      private: private,
      downloads: downloads,
      inserted_at: inserted_at,
      updated_at: updated_at,
      html_url: html_url,
      docs_html_url: docs_html_url,
      source: source
    }
  end

  defp release_to_map(
         {@releases_table, package_name, version, has_docs, meta, requirements, retired,
          downloads, inserted_at, updated_at, url, package_url, html_url, docs_html_url}
       ) do
    %{
      package_name: package_name,
      version: version,
      has_docs: has_docs,
      meta: meta,
      requirements: requirements,
      retired: retired,
      downloads: downloads,
      inserted_at: inserted_at,
      updated_at: updated_at,
      url: url,
      package_url: package_url,
      html_url: html_url,
      docs_html_url: docs_html_url
    }
  end

  defp validate_package_name(name) do
    cond do
      String.length(name) < 1 ->
        {:error, "Package name must not be empty"}

      String.length(name) > 100 ->
        {:error, "Package name must be at most 100 characters"}

      not String.match?(name, ~r/^[a-z][a-z0-9_]*$/) ->
        {:error,
         "Package name must start with lowercase letter and contain only lowercase letters, numbers, and underscores"}

      true ->
        :ok
    end
  end

  defp validate_version(version) do
    cond do
      String.length(version) < 1 ->
        {:error, "Version must not be empty"}

      not String.match?(version, ~r/^\d+\.\d+\.\d+.*$/) ->
        {:error, "Version must be in semantic versioning format"}

      true ->
        :ok
    end
  end

  @doc """
  List all unique repository names from packages.
  """
  @spec list_repositories() :: list(map())
  def list_repositories() do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn {_, _name, repository_name, _meta, _private, _downloads, _inserted_at,
                 _updated_at, _html_url, _docs_html_url, _source},
                acc ->
               MapSet.put(acc, repository_name)
             end,
             MapSet.new(),
             @packages_table
           )
         end) do
      {:atomic, repository_names} ->
        Enum.map(MapSet.to_list(repository_names), fn name ->
          %{
            name: name,
            package_count: count_packages_in_repository(name),
            inserted_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          }
        end)

      {:aborted, _reason} ->
        []
    end
  end

  @doc """
  Get a specific repository by name.
  """
  @spec get_repository(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_repository(name) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object({@packages_table, :_, name, :_, :_, :_, :_, :_, :_, :_, :_})
         end) do
      {:atomic, []} ->
        {:error, :not_found}

      {:atomic, packages} ->
        {:ok,
         %{
           name: name,
           package_count: length(packages),
           inserted_at: DateTime.utc_now(),
           updated_at: DateTime.utc_now()
         }}

      {:aborted, _reason} ->
        {:error, :not_found}
    end
  end

  @doc """
  Create a new repository. This is a logical operation since repositories
  are currently just names associated with packages.
  """
  @spec create_repository(map()) :: {:ok, map()} | {:error, map()}
  def create_repository(params) do
    name = params["name"] || params[:name]

    if String.trim(name) == "" do
      {:error, %{name: ["can't be blank"]}}
    else
      # Check if repository already exists
      case :mnesia.transaction(fn ->
             :mnesia.match_object({@packages_table, :_, name, :_, :_, :_, :_, :_, :_, :_, :_})
           end) do
        {:atomic, []} ->
          {:ok,
           %{
             name: name,
             package_count: 0,
             inserted_at: DateTime.utc_now(),
             updated_at: DateTime.utc_now()
           }}

        {:atomic, _packages} ->
          {:error, %{name: ["has already been taken"]}}

        {:aborted, _reason} ->
          {:error, %{name: ["database error"]}}
      end
    end
  end

  @doc """
  Update a repository name. This involves updating all packages in the repository.
  """
  @spec update_repository(String.t(), map()) :: {:ok, map()} | {:error, map()}
  def update_repository(old_name, params) do
    new_name = params["name"] || params[:name]

    if String.trim(new_name) == "" do
      {:error, %{name: ["can't be blank"]}}
    else
      case :mnesia.transaction(fn ->
             packages =
               :mnesia.match_object(
                 {@packages_table, :_, old_name, :_, :_, :_, :_, :_, :_, :_, :_}
               )

             # Update all packages with the new repository name
             Enum.each(packages, fn {table, pkg_name, _old_repo, meta, private, downloads,
                                     inserted_at, _updated_at, html_url, docs_html_url, source} ->
               updated_package = {
                 table,
                 pkg_name,
                 new_name,
                 meta,
                 private,
                 downloads,
                 inserted_at,
                 DateTime.utc_now(),
                 html_url,
                 docs_html_url,
                 source
               }

               :mnesia.write(updated_package)
             end)

             :ok
           end) do
        {:atomic, :ok} ->
          {:ok,
           %{
             name: new_name,
             package_count: count_packages_in_repository(new_name),
             inserted_at: DateTime.utc_now(),
             updated_at: DateTime.utc_now()
           }}

        {:aborted, _reason} ->
          {:error, %{name: ["update failed"]}}
      end
    end
  end

  @doc """
  Delete a repository. This involves deleting all packages in the repository.
  """
  @spec delete_repository(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def delete_repository(name) do
    case :mnesia.transaction(fn ->
           packages =
             :mnesia.match_object({@packages_table, :_, name, :_, :_, :_, :_, :_, :_, :_, :_})

           # Delete all packages in the repository
           Enum.each(packages, fn {table, pkg_name, _repo, _meta, _private, _downloads,
                                   _inserted_at, _updated_at, _html_url, _docs_html_url,
                                   _source} ->
             :mnesia.delete({table, pkg_name})
           end)

           # Also delete all releases for packages in this repository
           Enum.each(packages, fn {_table, pkg_name, _repo, _meta, _private, _downloads,
                                   _inserted_at, _updated_at, _html_url, _docs_html_url,
                                   _source} ->
             releases =
               :mnesia.match_object(
                 {@releases_table, pkg_name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
               )

             Enum.each(releases, fn {rel_table, _pkg_name, version, _has_docs, _meta,
                                     _requirements, _retired, _downloads, _inserted_at,
                                     _updated_at, _url, _package_url, _html_url,
                                     _docs_html_url} ->
               :mnesia.delete({rel_table, {pkg_name, version}})
             end)
           end)

           :ok
         end) do
      {:atomic, :ok} ->
        {:ok, name}

      {:aborted, _reason} ->
        {:error, "delete failed"}
    end
  end

  @doc """
  Delete a specific package and all its releases.
  """
  @spec delete_package(String.t()) :: {:ok, String.t()} | {:error, :not_found | String.t()}
  def delete_package(name) do
    case :mnesia.transaction(fn ->
           # Get the package first
           case :mnesia.read({@packages_table, name}) do
             [] ->
               {:error, :not_found}

             [_package] ->
               # Delete the package
               :mnesia.delete({@packages_table, name})

               # Delete all releases for this package
               releases =
                 :mnesia.match_object(
                   {@releases_table, name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
                 )

               Enum.each(releases, fn {rel_table, _pkg_name, version, _has_docs, _meta,
                                       _requirements, _retired, _downloads, _inserted_at,
                                       _updated_at, _url, _package_url, _html_url,
                                       _docs_html_url} ->
                 :mnesia.delete({rel_table, {name, version}})
               end)

               # Delete package owners
               owners =
                 :mnesia.match_object({@owners_table, name, :_})

               Enum.each(owners, fn {owner_table, _pkg_name, _username} ->
                 :mnesia.delete({owner_table, name})
               end)

               {:ok, name}
           end
         end) do
      {:atomic, {:ok, name}} ->
        {:ok, name}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, _reason} ->
        {:error, "delete failed"}
    end
  end

  @spec count_packages_in_repository(String.t()) :: integer()
  defp count_packages_in_repository(name) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object({@packages_table, :_, name, :_, :_, :_, :_, :_, :_, :_, :_})
         end) do
      {:atomic, packages} -> length(packages)
      {:aborted, _reason} -> 0
    end
  end

  @doc """
  Fetch package from upstream and cache it locally.
  """
  @spec fetch_package_from_upstream(String.t()) :: {:ok, package()} | {:error, :not_found}
  def fetch_package_from_upstream(package_name) do
    if not Upstream.enabled?() do
      {:error, :not_found}
    else
      case Upstream.fetch_package(package_name) do
        {:ok, upstream_package} ->
          # Create package locally with upstream metadata
          create_package_from_upstream(package_name, upstream_package)

        {:error, _reason} ->
          Telemetry.log(:warning, :package, "Failed to fetch package from upstream", %{
            package: package_name
          })

          {:error, :not_found}
      end
    end
  end

  @doc """
  Fetch release from upstream and cache it locally.
  """
  @spec fetch_release_from_upstream(String.t(), String.t()) ::
          {:ok, release()} | {:error, :not_found}
  def fetch_release_from_upstream(package_name, version) do
    if not Upstream.enabled?() do
      {:error, :not_found}
    else
      Telemetry.log(:debug, :package, "Starting upstream fetch", %{
        package: package_name,
        version: version
      })

      with {:ok, tarball} <- Upstream.fetch_release_tarball(package_name, version) do
        Telemetry.log(:debug, :package, "Step 1: Got tarball", %{size: byte_size(tarball)})

        with {:ok, releases} <- Upstream.fetch_releases(package_name) do
          Telemetry.log(:debug, :package, "Step 2: Got releases", %{count: length(releases)})

          release_info = Enum.find(releases, fn r -> r["version"] == version end)

          if release_info do
            Telemetry.log(:debug, :package, "Step 3: Found release info", %{version: version})

            with {:ok, _package} <- fetch_package_from_upstream(package_name) do
              Telemetry.log(:debug, :package, "Step 4: Got package info")

              meta = extract_release_meta(release_info)
              requirements = extract_requirements(release_info)
              Telemetry.log(:debug, :package, "Step 5: Extracted meta and requirements")

              # Cache the tarball
              case Upstream.cache_package(package_name, version, tarball, meta) do
                :ok ->
                  Telemetry.log(:debug, :package, "Step 6: Cached tarball successfully")
                  # Create release in local database
                  create_release_from_upstream(package_name, version, meta, requirements)

                {:error, reason} ->
                  Telemetry.log(
                    :error,
                    :package,
                    "Step 6 failed: Failed to cache release tarball",
                    %{
                      package: package_name,
                      version: version,
                      reason: reason
                    }
                  )

                  {:error, :not_found}
              end
            else
              {:error, reason} ->
                Telemetry.log(
                  :error,
                  :package,
                  "Step 4 failed: Failed to fetch package from upstream",
                  %{reason: reason}
                )

                {:error, :not_found}
            end
          else
            Telemetry.log(:error, :package, "Step 3 failed: Version not found in releases", %{
              version: version
            })

            {:error, :not_found}
          end
        else
          {:error, reason} ->
            Telemetry.log(:error, :package, "Step 2 failed: Failed to fetch releases", %{
              reason: reason
            })

            {:error, :not_found}
        end
      else
        {:error, reason} ->
          Telemetry.log(:error, :package, "Step 1 failed: Failed to fetch release tarball", %{
            reason: reason
          })

          {:error, :not_found}
      end
    end
  end

  @doc """
  Download package tarball with upstream fallback.
  """
  @spec download_package_with_upstream(String.t(), String.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def download_package_with_upstream(package_name, version) do
    # Try local download first
    case download_package(package_name, version) do
      {:ok, tarball} ->
        {:ok, tarball}

      {:error, _reason} ->
        # Try fetching from upstream and caching
        case fetch_release_from_upstream(package_name, version) do
          {:ok, _release} ->
            # Now try local download again
            download_package(package_name, version)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Download documentation tarball with upstream fallback.
  """
  @spec download_docs_with_upstream(String.t(), String.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def download_docs_with_upstream(package_name, version) do
    # Try local download first
    case download_docs(package_name, version) do
      {:ok, docs_tarball} ->
        {:ok, docs_tarball}

      {:error, _reason} ->
        # Try fetching from upstream
        if Upstream.enabled?() do
          case Upstream.fetch_docs_tarball(package_name, version) do
            {:ok, docs_tarball} ->
              # Cache the docs
              case Upstream.cache_docs(package_name, version, docs_tarball) do
                :ok ->
                  {:ok, docs_tarball}

                {:error, _reason} ->
                  Telemetry.log(:error, :package, "Failed to cache docs", %{
                    package: package_name,
                    version: version
                  })

                  # Still return the docs even if caching fails
                  {:ok, docs_tarball}
              end

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, "Documentation not found and upstream is disabled"}
        end
    end
  end

  ## Private helper functions for upstream processing

  defp create_package_from_upstream(package_name, upstream_package) do
    meta = %{
      "description" => upstream_package["meta"]["description"],
      "licenses" => upstream_package["meta"]["licenses"] || [],
      "links" => upstream_package["meta"]["links"] || %{},
      "maintainers" => upstream_package["meta"]["maintainers"] || [],
      "extra" => upstream_package["meta"]["extra"] || %{}
    }

    repository_name = upstream_package["repository"] || "hexpm"

    # Create as cached package (from upstream)
    create_package(package_name, repository_name, meta, false, :cached)
  end

  defp create_release_from_upstream(package_name, version, meta, requirements) do
    # Create a minimal release record
    now = DateTime.utc_now()

    release = {
      @releases_table,
      package_name,
      version,
      # has_docs - we don't know this yet
      false,
      meta,
      requirements,
      # retired
      false,
      # downloads
      0,
      now,
      now,
      "/packages/#{package_name}/releases/#{version}",
      "/packages/#{package_name}/releases/#{version}/package",
      "/packages/#{package_name}/releases/#{version}",
      "/packages/#{package_name}/releases/#{version}/docs"
    }

    case :mnesia.transaction(fn ->
           :mnesia.write(release)
         end) do
      {:atomic, :ok} ->
        release_map = release_to_map(release)
        {:ok, release_map}

      {:aborted, reason} ->
        {:error, "Failed to create release: #{inspect(reason)}"}
    end
  end

  defp extract_release_meta(release_info) do
    %{
      "app" => release_info["meta"]["app"],
      "build_tools" => release_info["meta"]["build_tools"] || [],
      "elixir" => release_info["meta"]["elixir"],
      "description" => release_info["meta"]["description"],
      "files" => release_info["meta"]["files"] || %{},
      "licenses" => release_info["meta"]["licenses"] || [],
      "links" => release_info["meta"]["links"] || %{},
      "maintainers" => release_info["meta"]["maintainers"] || []
    }
  end

  defp extract_requirements(release_info) do
    case release_info["requirements"] do
      requirements when is_map(requirements) ->
        requirements

      _ ->
        %{}
    end
  end
end
