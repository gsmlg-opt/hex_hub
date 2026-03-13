defmodule HexHub.MCP.Tools.Documentation do
  @moduledoc """
  MCP tools for documentation access and searching.

  Provides tools for accessing package documentation, listing
  documentation versions, and searching within documentation.
  """

  alias HexHub.{Packages, Storage}
  alias HexHub.Telemetry
  # alias HexHub.MCP.Tools.Packages, as: PackageTools # Unused alias removed

  @doc """
  Get documentation for a package.
  """
  def get_documentation(%{"name" => name} = args) do
    version = Map.get(args, "version")
    page = Map.get(args, "page", "index")

    Telemetry.log(:debug, :mcp, "MCP getting documentation", %{name: name, version: version})

    # Determine which version to use
    target_version =
      case version do
        nil -> get_latest_version_with_docs(name)
        v -> v
      end

    case target_version do
      nil ->
        {:error, :no_documentation_available}

      version ->
        source = Packages.get_package_source(name)
        doc_key = Storage.generate_docs_key(name, version, source)

        case Storage.exists?(doc_key) do
          true ->
            case get_documentation_page(name, version, page) do
              {:ok, content} ->
                result = %{
                  name: name,
                  version: version,
                  page: page,
                  content: content,
                  available_pages: list_documentation_pages(name, version),
                  documentation_urls: build_documentation_urls(name, version)
                }

                {:ok, result}

              {:error, reason} ->
                Telemetry.log(:error, :mcp, "MCP get documentation page failed", %{
                  reason: inspect(reason)
                })

                {:error, reason}
            end

          false ->
            Telemetry.log(:warning, :mcp, "MCP documentation not found", %{
              name: name,
              version: version
            })

            {:error, :documentation_not_found}
        end
    end
  end

  def get_documentation(_args) do
    {:error, :missing_package_name}
  end

  @doc """
  List available documentation versions for a package.
  """
  def list_documentation_versions(%{"name" => name}) do
    Telemetry.log(:debug, :mcp, "MCP listing documentation versions", %{name: name})

    {:ok, releases} = Packages.list_releases(name)

    doc_versions =
      releases
      |> Enum.filter(& &1.has_docs)
      |> Enum.map(&format_doc_version/1)

    result = %{
      name: name,
      documentation_versions: doc_versions,
      total_versions: length(doc_versions),
      latest_version: get_latest_version_with_docs(name)
    }

    {:ok, result}
  end

  def list_documentation_versions(_args) do
    {:error, :missing_package_name}
  end

  @doc """
  Search within package documentation.
  """
  def search_documentation(%{"name" => name, "query" => query} = args) do
    version = Map.get(args, "version")

    Telemetry.log(:debug, :mcp, "MCP searching documentation", %{name: name, query: query})

    # Determine which version to search
    target_version =
      case version do
        nil -> get_latest_version_with_docs(name)
        v -> v
      end

    case target_version do
      nil ->
        {:error, :no_documentation_available}

      version ->
        case search_in_documentation(name, version, query) do
          {:ok, search_results} ->
            result = %{
              name: name,
              version: version,
              query: query,
              results: search_results,
              total_matches: length(search_results),
              documentation_urls: build_documentation_urls(name, version)
            }

            {:ok, result}

          {:error, reason} ->
            Telemetry.log(:error, :mcp, "MCP documentation search failed", %{
              reason: inspect(reason)
            })

            {:error, reason}
        end
    end
  end

  def search_documentation(_args) do
    {:error, :missing_required_fields}
  end

  # Private helper functions

  defp get_latest_version_with_docs(name) do
    {:ok, releases} = Packages.list_releases(name)

    releases
    |> Enum.filter(& &1.has_docs)
    |> Enum.map(& &1.version)
    |> Enum.sort(&(Version.compare(&1, &2) == :gt))
    |> List.first()
  end

  defp get_documentation_page(name, version, page) do
    source = Packages.get_package_source(name)
    doc_key = Storage.generate_docs_key(name, version, source)

    case Storage.get(doc_key) do
      {:ok, doc_data} ->
        {:ok, content} = extract_page_from_tarball(doc_data, page)
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_page_from_tarball(_tarball_data, page) do
    # Extract and read a specific page from the documentation tarball
    # This would need to implement tarball extraction
    # For now, return a placeholder
    {:ok,
     "<html><body><h1>Documentation for #{page}</h1><p>Content placeholder</p></body></html>"}
  end

  defp list_documentation_pages(name, version) do
    source = Packages.get_package_source(name)
    doc_key = Storage.generate_docs_key(name, version, source)

    case Storage.get(doc_key) do
      {:ok, doc_data} ->
        {:ok, pages} = list_pages_in_tarball(doc_data)
        pages

      {:error, _} ->
        # fallback
        ["index.html"]
    end
  end

  defp list_pages_in_tarball(_tarball_data) do
    # List all HTML pages in the documentation tarball
    # This would need to implement tarball listing
    # For now, return a placeholder list
    {:ok, ["index.html", "api-reference.html", "guides.html", "examples.html"]}
  end

  defp search_in_documentation(name, version, query) do
    source = Packages.get_package_source(name)
    doc_key = Storage.generate_docs_key(name, version, source)

    case Storage.get(doc_key) do
      {:ok, doc_data} ->
        {:ok, results} = search_text_in_tarball(doc_data, query)
        formatted_results = Enum.map(results, &format_search_result/1)
        {:ok, formatted_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_text_in_tarball(_tarball_data, query) do
    # Search for text within all files in the documentation tarball
    # This would need to implement text search within tarball
    # For now, return placeholder results
    results = [
      %{
        file: "index.html",
        title: "Getting Started",
        snippet: "This is where you would find information about #{query}...",
        line_number: 42,
        relevance_score: 0.9
      },
      %{
        file: "api-reference.html",
        title: "API Reference",
        snippet: "The #{query} function provides the following capabilities...",
        line_number: 128,
        relevance_score: 0.8
      }
    ]

    {:ok, results}
  end

  defp format_search_result(result) do
    %{
      file: result.file,
      title: result.title,
      snippet: result.snippet,
      line_number: result.line_number,
      relevance_score: result.relevance_score,
      url: "/#{result.file}#line-#{result.line_number}"
    }
  end

  defp format_doc_version(release) do
    %{
      version: release.version,
      has_docs: release.has_docs,
      inserted_at: release.inserted_at,
      documentation_url: build_documentation_url(release.package_name, release.version)
    }
  end

  defp build_documentation_urls(name, version) do
    %{
      web: "/docs/#{name}-#{version}",
      api: "/api/packages/#{name}/releases/#{version}/docs",
      html: "/packages/#{name}/#{version}/docs",
      tarball: "/docs/#{name}-#{version}.tar.gz"
    }
  end

  defp build_documentation_url(name, version) do
    "/docs/#{name}-#{version}"
  end

  @doc """
  Validate get documentation arguments.
  """
  def validate_get_docs_args(args) do
    required_fields = ["name"]
    optional_fields = ["version", "page"]

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate list documentation versions arguments.
  """
  def validate_list_versions_args(args) do
    required_fields = ["name"]
    optional_fields = []

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate search documentation arguments.
  """
  def validate_search_docs_args(args) do
    required_fields = ["name", "query"]
    optional_fields = ["version"]

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Generic field validation

  defp validate_fields(args, required, optional) do
    # Check required fields
    missing_required =
      Enum.filter(required, fn field ->
        not Map.has_key?(args, field) or is_nil(Map.get(args, field))
      end)

    if length(missing_required) > 0 do
      {:error, {:missing_required_fields, missing_required}}
    else
      # Check for unknown fields
      known_fields = required ++ optional

      unknown_fields =
        Enum.filter(Map.keys(args), fn field ->
          field not in known_fields
        end)

      if length(unknown_fields) > 0 do
        Telemetry.log(:warning, :mcp, "Unknown fields in args", %{
          unknown_fields: inspect(unknown_fields)
        })
      end

      :ok
    end
  end

  @doc """
  Get documentation statistics for monitoring.
  """
  def get_documentation_stats do
    %{
      total_packages_with_docs: get_packages_with_docs_count(),
      total_documentation_releases: get_documentation_releases_count(),
      documentation_storage_size: get_documentation_storage_size(),
      avg_docs_per_package: calculate_avg_docs_per_package(),
      recent_documentation_updates: get_recent_docs_updates_count()
    }
  end

  defp get_packages_with_docs_count do
    # Count packages that have at least one release with documentation
    # This would require a database query
    0
  end

  defp get_documentation_releases_count do
    # Count releases that have documentation
    # This would require a database query
    0
  end

  defp get_documentation_storage_size do
    # Calculate total storage used by documentation
    # This would require scanning the storage
    0
  end

  defp calculate_avg_docs_per_package do
    total_packages = :mnesia.table_info(:packages, :size)
    doc_releases = get_documentation_releases_count()

    if total_packages > 0 do
      doc_releases / total_packages
    else
      0
    end
  end

  defp get_recent_docs_updates_count do
    # Count documentation updates in the last 30 days
    # This would require a database query with date filtering
    0
  end

  @doc """
  Log documentation operation for telemetry.
  """
  def log_documentation_operation(operation, package_name, version, metadata \\ %{}) do
    :telemetry.execute(
      [:hex_hub, :mcp, :documentation],
      %{
        operation: operation,
        package_name: package_name,
        version: version
      },
      metadata
    )
  end

  @doc """
  Check if documentation exists for a package version.
  """
  def documentation_exists?(name, version) do
    source = Packages.get_package_source(name)
    doc_key = Storage.generate_docs_key(name, version, source)
    Storage.exists?(doc_key)
  end

  @doc """
  Get documentation size in bytes.
  """
  def get_documentation_size(name, version) do
    source = Packages.get_package_source(name)
    doc_key = Storage.generate_docs_key(name, version, source)

    case Storage.exists?(doc_key) do
      true ->
        # This would need Storage to support size queries
        # For now, return 0
        0

      false ->
        {:error, :documentation_not_found}
    end
  end

  @doc """
  Get documentation index for a package version.
  """
  def get_documentation_index(name, version) do
    case get_documentation_page(name, version, "index") do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extract documentation metadata.
  """
  def extract_documentation_metadata(name, version) do
    # Extract metadata like title, description from documentation
    # This would need to parse the documentation files
    %{
      title: "#{name} v#{version} Documentation",
      description: "Documentation for #{name} package version #{version}",
      language: "en",
      format: "html",
      generated_at: DateTime.utc_now()
    }
  end
end
