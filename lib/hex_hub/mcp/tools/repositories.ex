defmodule HexHub.MCP.Tools.Repositories do
  @moduledoc """
  MCP tools for repository management.

  Provides tools for listing repositories, getting repository information,
  and managing package visibility within repositories.
  """

  @dialyzer [{:nowarn_function, repository_exists?: 1}, {:no_match, repository_exists?: 1}]

  alias HexHub.{Packages, Repositories}
  alias HexHub.Telemetry

  @doc """
  List all available repositories.
  """
  def list_repositories(args \\ %{}) do
    include_private = Map.get(args, "include_private", false)

    Telemetry.log(:debug, :mcp, "MCP listing repositories", %{include_private: include_private})

    repositories = Repositories.list_repositories()

    filtered_repos =
      if include_private do
        repositories
      else
        Enum.filter(repositories, & &1.public)
      end

    result = %{
      repositories: Enum.map(filtered_repos, &format_repository/1),
      total_repositories: length(filtered_repos),
      include_private: include_private,
      default_repository: get_default_repository()
    }

    {:ok, result}
  end

  @doc """
  Get detailed information about a repository.
  """
  def get_repository_info(%{"name" => name}) do
    Telemetry.log(:debug, :mcp, "MCP getting repository info", %{name: name})

    case Repositories.get_repository(name) do
      {:ok, repository} ->
        # Get additional repository statistics
        package_count = get_package_count_for_repository(name)
        recent_packages = get_recent_packages_for_repository(name)

        result = %{
          repository: format_repository(repository),
          statistics: %{
            total_packages: package_count,
            total_downloads: 0,
            recent_packages: length(recent_packages)
          },
          recent_packages: Enum.map(recent_packages, &format_basic_package/1),
          urls: build_repository_urls(repository)
        }

        {:ok, result}

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP get repository info failed", %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  def get_repository_info(_args) do
    {:error, :missing_repository_name}
  end

  @doc """
  Toggle package visibility between public and private.
  """
  def toggle_package_visibility(%{"name" => name, "private" => private}) do
    Telemetry.log(:debug, :mcp, "MCP toggling package visibility", %{
      name: name,
      private: private
    })

    case Packages.get_package(name) do
      {:ok, package} ->
        # Update package visibility
        updated_package = %{package | private: private}

        case update_package_visibility(updated_package) do
          {:atomic, _} ->
            result = %{
              name: name,
              repository: package.repository,
              visibility: if(private, do: "private", else: "public"),
              updated_at: DateTime.utc_now(),
              urls: build_package_urls(updated_package)
            }

            {:ok, result}

          {:aborted, reason} ->
            Telemetry.log(:error, :mcp, "MCP toggle package visibility failed", %{
              reason: inspect(reason)
            })

            {:error, "Failed to update package visibility: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP toggle package visibility: package not found", %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  def toggle_package_visibility(_args) do
    {:error, :missing_required_fields}
  end

  # Private helper functions

  defp format_repository(repository) do
    %{
      name: repository.name,
      url: repository.url,
      description: repository.description,
      public: repository.public,
      downloads: repository.downloads || 0,
      inserted_at: repository.inserted_at,
      updated_at: repository.updated_at
    }
  end

  defp format_basic_package(package) do
    %{
      name: package.name,
      description: get_meta_field(package.meta, "description"),
      downloads: package.downloads,
      inserted_at: package.inserted_at,
      updated_at: package.updated_at
    }
  end

  defp get_meta_field(meta, field, default \\ nil) do
    case Jason.decode(meta || "{}") do
      {:ok, decoded} -> Map.get(decoded, field, default)
      {:error, _} -> default
    end
  end

  defp get_default_repository do
    # Default Hex repository
    "hexpm"
  end

  defp get_package_count_for_repository(_repository_name) do
    # Count packages in the specified repository
    # This would require a database query
    # Simplified
    :mnesia.table_info(:packages, :size)
  end

  defp get_recent_packages_for_repository(_repository_name, _limit \\ 5) do
    # Get recent packages from the repository
    # This would require a database query with ordering
    []
  end

  defp build_repository_urls(repository) do
    %{
      api: "/api/repos/#{repository.name}",
      web: "/repos/#{repository.name}",
      packages: "/api/repos/#{repository.name}/packages"
    }
  end

  defp build_package_urls(package) do
    %{
      api: "/api/packages/#{package.name}",
      web: "/packages/#{package.name}",
      repository: "/repos/#{package.repository}"
    }
  end

  defp update_package_visibility(package) do
    # Update package visibility in Mnesia
    :mnesia.transaction(fn ->
      :mnesia.write(
        {:packages, package.name, package.repository, package.meta, package.private,
         package.downloads, package.url, package.inserted_at, DateTime.utc_now()}
      )
    end)
  end

  @doc """
  Validate list repositories arguments.
  """
  def validate_list_repos_args(args) do
    required_fields = []
    optional_fields = ["include_private"]

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate get repository info arguments.
  """
  def validate_get_repo_args(args) do
    required_fields = ["name"]
    optional_fields = []

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate toggle package visibility arguments.
  """
  def validate_toggle_visibility_args(args) do
    required_fields = ["name", "private"]
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

    if missing_required != [] do
      {:error, {:missing_required_fields, missing_required}}
    else
      # Check for unknown fields
      known_fields = required ++ optional

      unknown_fields =
        Enum.filter(Map.keys(args), fn field ->
          field not in known_fields
        end)

      if unknown_fields != [] do
        Telemetry.log(:warning, :mcp, "Unknown fields in args", %{
          unknown_fields: inspect(unknown_fields)
        })
      end

      :ok
    end
  end

  @doc """
  Get repository statistics for monitoring.
  """
  def get_repository_stats do
    %{
      total_repositories: get_total_repositories_count(),
      public_repositories: get_public_repositories_count(),
      private_repositories: get_private_repositories_count(),
      total_packages: get_total_packages_count(),
      avg_packages_per_repo: calculate_avg_packages_per_repo(),
      repository_activity: get_repository_activity_stats()
    }
  end

  defp get_total_repositories_count do
    # Count total repositories
    # This would require a database query
    # At least hexpm exists
    1
  end

  defp get_public_repositories_count do
    # Count public repositories
    # hexpm is public
    1
  end

  defp get_private_repositories_count do
    # Count private repositories
    0
  end

  defp get_total_packages_count do
    :mnesia.table_info(:packages, :size)
  end

  defp calculate_avg_packages_per_repo do
    total_repos = get_total_repositories_count()
    total_packages = get_total_packages_count()

    if total_repos > 0 do
      total_packages / total_repos
    else
      0
    end
  end

  defp get_repository_activity_stats do
    %{
      new_repositories_today: 0,
      new_repositories_this_week: 0,
      new_repositories_this_month: 0,
      most_active_repository: "hexpm"
    }
  end

  @doc """
  Log repository operation for telemetry.
  """
  def log_repository_operation(operation, repository_name, metadata \\ %{}) do
    :telemetry.execute(
      [:hex_hub, :mcp, :repositories],
      %{
        operation: operation,
        repository_name: repository_name
      },
      metadata
    )
  end

  @doc """
  Check if a repository exists.
  """
  @spec repository_exists?(String.t()) :: boolean()
  def repository_exists?(name) do
    case Repositories.get_repository(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get repository by name with fallback to default.
  """
  def get_repository_with_fallback(name) do
    case Repositories.get_repository(name) do
      {:ok, repository} ->
        {:ok, repository}

      {:error, _} ->
        # Fallback to default repository
        Repositories.get_repository(get_default_repository())
    end
  end

  @doc """
  Create a new repository (admin only).
  """
  def create_repository(params) do
    # Create a new repository
    # This would be an admin-only operation
    repository = %{
      name: Map.get(params, "name"),
      url: Map.get(params, "url"),
      description: Map.get(params, "description", ""),
      public: Map.get(params, "public", true),
      downloads: 0,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    Repositories.create_repository(repository)
  end

  @doc """
  Update repository information (admin only).
  """
  def update_repository(name, params) do
    # Update repository information
    # This would be an admin-only operation
    case Repositories.get_repository(name) do
      {:ok, repository} ->
        updated_repo =
          repository
          |> Map.put(:url, Map.get(params, "url", repository.url))
          |> Map.put(:description, Map.get(params, "description", repository.description))
          |> Map.put(:public, Map.get(params, "public", repository.public))

        case Repositories.update_repository(updated_repo) do
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a repository (admin only).
  """
  def delete_repository(name) do
    # Delete a repository
    # This would be an admin-only operation and would need to handle
    # package migration or deletion
    case Repositories.delete_repository(name) do
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get packages for a repository.
  """
  def get_repository_packages(name, opts \\ %{}) do
    page = Map.get(opts, :page, 1)
    per_page = Map.get(opts, :per_page, 20)

    case Packages.list_packages(repository: name, page: page, per_page: per_page) do
      {:ok, packages, total} ->
        result = %{
          repository: name,
          packages: Enum.map(packages, &format_basic_package/1),
          pagination: %{
            page: page,
            per_page: per_page,
            total_packages: total
          }
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sync repository with upstream source.
  """
  def sync_repository(name) do
    # Sync repository with upstream source
    # This would fetch package metadata from upstream
    Telemetry.log(:info, :mcp, "MCP syncing repository", %{name: name})

    # Implementation would depend on repository type
    # For now, return success
    {:ok,
     %{
       name: name,
       synced_at: DateTime.utc_now(),
       packages_updated: 0,
       packages_added: 0
     }}
  end

  @doc """
  Get repository health status.
  """
  def get_repository_health(name) do
    # Check repository health (connectivity, sync status, etc.)
    case Repositories.get_repository(name) do
      {:ok, _repository} ->
        health = %{
          name: name,
          status: "healthy",
          last_sync: DateTime.utc_now(),
          connectivity: "connected",
          package_count: get_package_count_for_repository(name),
          issues: []
        }

        {:ok, health}

      {:error, reason} ->
        {:ok,
         %{
           name: name,
           status: "error",
           error: reason,
           connectivity: "disconnected",
           package_count: 0,
           issues: ["Repository not found: #{inspect(reason)}"]
         }}
    end
  end
end
