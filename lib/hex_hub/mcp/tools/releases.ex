defmodule HexHub.MCP.Tools.Releases do
  @moduledoc """
  MCP tools for package release management.

  Provides tools for listing releases, getting release details,
  downloading packages, and comparing releases.
  """

  alias HexHub.{Packages, Storage}
  alias HexHub.Telemetry
  # alias HexHub.MCP.Tools.Packages, as: PackageTools # Unused alias removed

  @doc """
  List all releases/versions for a package.
  """
  def list_releases(%{"name" => name} = args) do
    include_retired = Map.get(args, "include_retired", false)

    Telemetry.log(:debug, :mcp, "MCP listing releases", %{name: name})

    {:ok, releases} = Packages.list_releases(name)

    filtered_releases =
      if include_retired do
        releases
      else
        Enum.reject(releases, &(&1.retirement != nil))
      end

    result = %{
      package_name: name,
      releases: Enum.map(filtered_releases, &format_release/1),
      total_releases: length(filtered_releases),
      include_retired: include_retired,
      latest_version: get_latest_version(releases)
    }

    {:ok, result}
  end

  def list_releases(_args) do
    {:error, :missing_package_name}
  end

  @doc """
  Get detailed information about a specific package release.
  """
  def get_release(%{"name" => name, "version" => version} = _args) do
    Telemetry.log(:debug, :mcp, "MCP getting release info", %{name: name, version: version})

    case Packages.get_release(name, version) do
      {:ok, release} ->
        metadata = Jason.decode!(release.metadata || "{}")
        requirements = parse_requirements(release.requirements)

        result = %{
          name: name,
          version: release.version,
          metadata: metadata,
          requirements: requirements,
          has_docs: release.has_docs,
          retirement_info: get_retirement_info(release),
          inserted_at: release.inserted_at,
          checksum: release.checksum,
          download_urls: build_download_urls(name, version),
          documentation_urls: build_documentation_urls(name, version, release.has_docs)
        }

        {:ok, result}

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP get release failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  def get_release(_args) do
    {:error, :missing_required_fields}
  end

  @doc """
  Download a package release tarball.
  """
  def download_release(%{"name" => name, "version" => version}) do
    Telemetry.log(:debug, :mcp, "MCP downloading package", %{name: name, version: version})

    source = Packages.get_package_source(name)
    tarball_key = Storage.generate_package_key(name, version, source)

    case Storage.exists?(tarball_key) do
      true ->
        case Storage.get(tarball_key) do
          {:ok, tarball_data} ->
            result = %{
              name: name,
              version: version,
              tarball_data: Base.encode64(tarball_data),
              size: byte_size(tarball_data),
              checksum: calculate_checksum(tarball_data),
              download_url: build_download_url(name, version)
            }

            {:ok, result}

          {:error, reason} ->
            Telemetry.log(:error, :mcp, "MCP download release failed to read tarball", %{
              reason: inspect(reason)
            })

            {:error, reason}
        end

      false ->
        Telemetry.log(:warning, :mcp, "MCP download release: tarball not found", %{
          name: name,
          version: version
        })

        {:error, :tarball_not_found}
    end
  end

  def download_release(_args) do
    {:error, :missing_required_fields}
  end

  @doc """
  Compare two different releases of a package.
  """
  def compare_releases(%{"name" => name, "version1" => version1, "version2" => version2}) do
    Telemetry.log(:debug, :mcp, "MCP comparing releases", %{
      name: name,
      version1: version1,
      version2: version2
    })

    with {:ok, release1} <- Packages.get_release(name, version1),
         {:ok, release2} <- Packages.get_release(name, version2) do
      metadata1 = Jason.decode!(release1.metadata || "{}")
      metadata2 = Jason.decode!(release2.metadata || "{}")

      requirements1 = parse_requirements(release1.requirements)
      requirements2 = parse_requirements(release2.requirements)

      comparison = %{
        name: name,
        version1: version1,
        version2: version2,
        version_comparison: compare_versions(version1, version2),
        metadata_diff: compare_metadata(metadata1, metadata2),
        requirements_diff: compare_requirements(requirements1, requirements2),
        docs_diff: %{
          v1_has_docs: release1.has_docs,
          v2_has_docs: release2.has_docs,
          docs_added: release2.has_docs and not release1.has_docs,
          docs_removed: release1.has_docs and not release2.has_docs
        },
        release_info_diff: %{
          v1_inserted_at: release1.inserted_at,
          v2_inserted_at: release2.inserted_at,
          v1_retired: release1.retirement != nil,
          v2_retired: release2.retirement != nil
        }
      }

      {:ok, comparison}
    else
      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP compare releases failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  def compare_releases(_args) do
    {:error, :missing_required_fields}
  end

  # Private helper functions

  defp format_release(release) do
    %{
      version: release.version,
      has_docs: release.has_docs,
      inserted_at: release.inserted_at,
      retirement_info: get_retirement_info(release),
      checksum: release.checksum,
      download_url: build_download_url(release.package_name, release.version)
    }
  end

  defp parse_requirements(requirements) when is_map(requirements), do: requirements

  defp get_retirement_info(release) do
    case release.retirement do
      nil ->
        nil

      retirement ->
        %{
          reason: retirement.reason,
          message: retirement.message
        }
    end
  end

  defp build_download_urls(name, version) do
    %{
      tarball: build_download_url(name, version),
      api: "/api/packages/#{name}/releases/#{version}",
      html: "/packages/#{name}/releases/#{version}"
    }
  end

  defp build_documentation_urls(name, version, has_docs) do
    if has_docs do
      %{
        documentation: "/docs/#{name}-#{version}",
        api: "/api/packages/#{name}/releases/#{version}/docs",
        html: "/packages/#{name}/#{version}/docs"
      }
    else
      %{documentation: nil, api: nil, html: nil}
    end
  end

  defp build_download_url(name, version) do
    "/tarballs/#{name}-#{version}.tar.gz"
  end

  defp calculate_checksum(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp compare_versions(version1, version2) do
    case Version.compare(version1, version2) do
      :gt -> "version1 is newer than version2"
      :lt -> "version1 is older than version2"
      :eq -> "versions are equal"
    end
  end

  defp compare_metadata(meta1, meta2) do
    # Compare metadata fields
    all_keys = (Map.keys(meta1) ++ Map.keys(meta2)) |> Enum.uniq()

    Enum.into(all_keys, %{}, fn key ->
      value1 = Map.get(meta1, key)
      value2 = Map.get(meta2, key)

      diff =
        cond do
          is_nil(value1) and not is_nil(value2) -> :added
          not is_nil(value1) and is_nil(value2) -> :removed
          value1 != value2 -> :changed
          true -> :unchanged
        end

      {key,
       %{
         status: diff,
         v1_value: value1,
         v2_value: value2
       }}
    end)
  end

  defp compare_requirements(reqs1, reqs2) do
    all_deps = (Map.keys(reqs1) ++ Map.keys(reqs2)) |> Enum.uniq()

    Enum.into(all_deps, %{}, fn dep ->
      req1 = Map.get(reqs1, dep)
      req2 = Map.get(reqs2, dep)

      diff =
        cond do
          is_nil(req1) and not is_nil(req2) -> :added
          not is_nil(req1) and is_nil(req2) -> :removed
          req1 != req2 -> :changed
          true -> :unchanged
        end

      {dep,
       %{
         status: diff,
         v1_requirement: req1,
         v2_requirement: req2
       }}
    end)
  end

  @doc """
  Validate list releases arguments.
  """
  def validate_list_releases_args(args) do
    required_fields = ["name"]
    optional_fields = ["include_retired"]

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate get release arguments.
  """
  def validate_get_release_args(args) do
    required_fields = ["name", "version"]
    optional_fields = []

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate download release arguments.
  """
  def validate_download_args(args) do
    validate_get_release_args(args)
  end

  @doc """
  Validate compare releases arguments.
  """
  def validate_compare_args(args) do
    required_fields = ["name", "version1", "version2"]
    optional_fields = []

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
  Get release statistics for monitoring.
  """
  def get_release_stats do
    %{
      total_releases: get_total_releases_count(),
      releases_with_docs: get_releases_with_docs_count(),
      retired_releases: get_retired_releases_count(),
      avg_releases_per_package: calculate_avg_releases_per_package(),
      recent_releases: get_recent_releases_count()
    }
  end

  defp get_total_releases_count do
    :mnesia.table_info(:package_releases, :size)
  end

  defp get_releases_with_docs_count do
    # Count releases with has_docs = true
    # This would require a database query
    0
  end

  defp get_retired_releases_count do
    # Count releases with retirement info
    # This would require a database query
    0
  end

  defp calculate_avg_releases_per_package do
    total_packages = :mnesia.table_info(:packages, :size)
    total_releases = :mnesia.table_info(:package_releases, :size)

    if total_packages > 0 do
      total_releases / total_packages
    else
      0
    end
  end

  defp get_recent_releases_count do
    # Count releases from the last 30 days
    # This would require a database query with date filtering
    0
  end

  @doc """
  Log release operation for telemetry.
  """
  def log_release_operation(operation, package_name, version, metadata \\ %{}) do
    :telemetry.execute(
      [:hex_hub, :mcp, :releases],
      %{
        operation: operation,
        package_name: package_name,
        version: version
      },
      metadata
    )
  end

  @doc """
  Check if a release exists.
  """
  def release_exists?(name, version) do
    case Packages.get_release(name, version) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get release size in bytes.
  """
  def get_release_size(name, version) do
    source = Packages.get_package_source(name)
    tarball_key = Storage.generate_package_key(name, version, source)

    case Storage.exists?(tarball_key) do
      true ->
        # This would need Storage to support size queries
        # For now, return 0
        0

      false ->
        {:error, :tarball_not_found}
    end
  end

  # Helper function to get the latest version from a list of releases
  defp get_latest_version(releases) when is_list(releases) do
    releases
    |> Enum.map(& &1.version)
    |> Enum.sort(&(Version.compare(&2, &1) == :gt))
    |> List.first()
  end
end
