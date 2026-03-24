defmodule HexHub.MCP.Tools.Dependencies do
  @moduledoc """
  MCP tools for dependency resolution and analysis.

  Provides tools for resolving Mix-style dependencies, building
  dependency trees, and checking version compatibility.
  """

  alias HexHub.Packages
  alias HexHub.Telemetry
  # alias HexHub.MCP.Tools.Packages, as: PackageTools # Unused alias removed

  @doc """
  Resolve Mix-style dependencies for a project.
  """
  def resolve_dependencies(%{"requirements" => requirements} = args) do
    elixir_version = Map.get(args, "elixir_version", get_current_elixir_version())

    Telemetry.log(:debug, :mcp, "MCP resolving dependencies", %{elixir_version: elixir_version})

    case parse_requirements(requirements) do
      {:ok, parsed_requirements} ->
        case do_dependency_resolution(parsed_requirements, elixir_version) do
          {:ok, resolution} ->
            result = %{
              elixir_version: elixir_version,
              requirements: parsed_requirements,
              resolution: format_resolution(resolution),
              conflicts: find_conflicts(resolution),
              total_packages: length(resolution),
              resolution_time: get_resolution_time()
            }

            {:ok, result}

          {:error, reason} ->
            Telemetry.log(:error, :mcp, "MCP dependency resolution failed", %{
              reason: inspect(reason)
            })

            {:error, reason}
        end

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP failed to parse requirements", %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  def resolve_dependencies(_args) do
    {:error, :missing_requirements}
  end

  @doc """
  Build dependency tree for a package.
  """
  def get_dependency_tree(%{"name" => name, "version" => version} = args) do
    max_depth = Map.get(args, "depth", 10)

    Telemetry.log(:debug, :mcp, "MCP building dependency tree", %{name: name, version: version})

    case build_dependency_tree(name, version, max_depth) do
      {:ok, tree} ->
        result = %{
          root_package: %{
            name: name,
            version: version
          },
          dependency_tree: tree,
          tree_stats: calculate_tree_stats(tree),
          max_depth: max_depth,
          total_dependencies: count_total_dependencies(tree)
        }

        {:ok, result}

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP dependency tree building failed", %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  def get_dependency_tree(_args) do
    {:error, :missing_required_fields}
  end

  @doc """
  Check version compatibility between packages.
  """
  def check_compatibility(%{"packages" => packages} = args) do
    elixir_version = Map.get(args, "elixir_version", get_current_elixir_version())

    Telemetry.log(:debug, :mcp, "MCP checking compatibility", %{
      package_count: length(packages)
    })

    case parse_package_list(packages) do
      {:ok, parsed_packages} ->
        compatibility_result = analyze_compatibility(parsed_packages, elixir_version)

        result = %{
          elixir_version: elixir_version,
          packages: parsed_packages,
          compatibility: compatibility_result,
          recommendations: generate_recommendations(compatibility_result),
          warnings: extract_warnings(compatibility_result)
        }

        {:ok, result}

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP compatibility check failed", %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  def check_compatibility(_args) do
    {:error, :missing_package_list}
  end

  # Private helper functions

  defp parse_requirements(requirements) when is_map(requirements) do
    # Parse Mix-style requirements map
    parsed =
      Enum.map(requirements, fn {package, requirement} ->
        case parse_requirement_string(requirement) do
          {:ok, parsed_req} -> {package, parsed_req}
          {:error, reason} -> {:error, {package, reason}}
        end
      end)

    errors = Enum.filter(parsed, &match?({:error, _}, &1))

    if errors != [] do
      {:error, {:invalid_requirements, errors}}
    else
      {:ok, Enum.into(parsed, %{})}
    end
  end

  defp parse_requirements(_), do: {:error, :invalid_requirements_format}

  defp parse_requirement_string(req_string) when is_binary(req_string) do
    # Parse requirement strings like "~> 1.2.0", ">= 1.0.0", etc.
    try do
      # Use Mix's requirement parsing if available
      {:ok, requirement} = Version.parse_requirement(req_string)
      {:ok, requirement}
    rescue
      _ -> {:error, :invalid_requirement_format}
    end
  end

  defp parse_requirement_string(_), do: {:error, :invalid_requirement_type}

  defp do_dependency_resolution(requirements, elixir_version) do
    # Implement dependency resolution algorithm
    # This is a simplified version - a real implementation would use
    # pubgrub or similar dependency resolution algorithm

    resolved =
      Enum.map(requirements, fn {package, requirement} ->
        case find_suitable_version(package, requirement, elixir_version) do
          {:ok, version} -> {package, version}
          {:error, reason} -> {:error, {package, reason}}
        end
      end)

    errors = Enum.filter(resolved, &match?({:error, _}, &1))

    if errors != [] do
      {:error, {:resolution_failed, errors}}
    else
      {:ok, Enum.filter(resolved, &match?({_, _}, &1))}
    end
  end

  defp find_suitable_version(package, requirement, elixir_version) do
    {:ok, releases} = Packages.list_releases(package)

    suitable_versions =
      releases
      |> Enum.map(& &1.version)
      |> Enum.filter(fn version ->
        Version.match?(version, requirement) and
          compatible_with_elixir?(package, version, elixir_version)
      end)
      |> Enum.sort(&(Version.compare(&1, &2) == :gt))

    case suitable_versions do
      [version | _] -> {:ok, version}
      [] -> {:error, :no_suitable_version}
    end
  end

  defp compatible_with_elixir?(package, version, elixir_version) do
    # Check if package version is compatible with Elixir version
    # This would check package metadata for elixir requirements
    case Packages.get_release(package, version) do
      {:ok, release} ->
        metadata = Jason.decode!(release.metadata || "{}")
        elixir_req = Map.get(metadata, "elixir")

        case elixir_req do
          # No Elixir requirement specified
          nil ->
            true

          req ->
            try do
              {:ok, requirement} = Version.parse_requirement(req)
              Version.match?(elixir_version, requirement)
            rescue
              _ -> true
            end
        end

      {:error, _} ->
        # Assume compatible if we can't check
        true
    end
  end

  defp format_resolution(resolution) do
    Enum.map(resolution, fn {package, version} ->
      %{
        name: package,
        version: version,
        source: "hex",
        checksum: get_package_checksum(package, version)
      }
    end)
  end

  defp find_conflicts(_resolution) do
    # Find version conflicts between dependencies
    # This would analyze the resolution for conflicts
    []
  end

  defp get_resolution_time do
    # Return time taken for resolution (placeholder)
    # milliseconds
    50
  end

  defp build_dependency_tree(name, version, max_depth, current_depth \\ 0) do
    if current_depth >= max_depth do
      {:ok, %{name: name, version: version, truncated: true}}
    else
      build_tree_for_release(name, version, max_depth, current_depth)
    end
  end

  defp build_tree_for_release(name, version, max_depth, current_depth) do
    case Packages.get_release(name, version) do
      {:ok, release} ->
        requirements = parse_release_requirements(release.requirements)
        dependencies = resolve_dependencies_for_tree(requirements, max_depth, current_depth)
        {:ok, %{name: name, version: version, dependencies: dependencies, depth: current_depth}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_dependencies_for_tree(requirements, max_depth, current_depth) do
    Enum.map(requirements, fn {dep_name, req} ->
      resolve_single_dependency(dep_name, req, max_depth, current_depth + 1)
    end)
  end

  defp resolve_single_dependency(dep_name, req, max_depth, next_depth) do
    case find_suitable_version(dep_name, req, get_current_elixir_version()) do
      {:ok, dep_version} ->
        build_tree_or_error(dep_name, dep_version, max_depth, next_depth)

      {:error, _} ->
        %{name: dep_name, version: req, unresolved: true}
    end
  end

  defp build_tree_or_error(dep_name, dep_version, max_depth, next_depth) do
    case build_dependency_tree(dep_name, dep_version, max_depth, next_depth) do
      {:ok, dep_tree} -> dep_tree
      {:error, _} -> %{name: dep_name, error: true}
    end
  end

  defp parse_release_requirements(requirements) when is_map(requirements), do: requirements

  defp calculate_tree_stats(tree) do
    %{
      max_depth: calculate_max_depth(tree),
      total_nodes: count_nodes(tree),
      leaf_nodes: count_leaf_nodes(tree),
      average_branching_factor: calculate_avg_branching(tree)
    }
  end

  defp calculate_max_depth(tree) do
    case Map.get(tree, :dependencies, []) do
      [] ->
        Map.get(tree, :depth, 0)

      deps ->
        deps
        |> Enum.map(&calculate_max_depth/1)
        |> Enum.max()
        |> Kernel.+(1)
    end
  end

  defp count_nodes(tree) do
    deps = Map.get(tree, :dependencies, [])
    1 + Enum.sum(Enum.map(deps, &count_nodes/1))
  end

  defp count_leaf_nodes(tree) do
    deps = Map.get(tree, :dependencies, [])

    if Enum.empty?(deps) do
      1
    else
      Enum.sum(Enum.map(deps, &count_leaf_nodes/1))
    end
  end

  defp calculate_avg_branching(tree) do
    deps = Map.get(tree, :dependencies, [])

    if Enum.empty?(deps) do
      0
    else
      total_deps =
        Enum.sum(
          Enum.map(deps, fn dep ->
            length(Map.get(dep, :dependencies, []))
          end)
        )

      total_deps / length(deps)
    end
  end

  defp count_total_dependencies(tree) do
    # Exclude root package
    count_nodes(tree) - 1
  end

  defp parse_package_list(packages) when is_list(packages) do
    parsed =
      Enum.map(packages, fn package ->
        case parse_package_entry(package) do
          {:ok, parsed} -> parsed
          {:error, reason} -> {:error, reason}
        end
      end)

    errors = Enum.filter(parsed, &match?({:error, _}, &1))

    if errors != [] do
      {:error, {:invalid_packages, errors}}
    else
      {:ok, Enum.filter(parsed, &match?({_, _}, &1))}
    end
  end

  defp parse_package_entry(%{"name" => name, "version" => version}) do
    {:ok, {name, version}}
  end

  defp parse_package_entry(_), do: {:error, :invalid_package_entry}

  defp analyze_compatibility(packages, elixir_version) do
    # Analyze compatibility between the specified packages
    compatibility_matrix =
      Enum.map(packages, fn {name1, version1} ->
        compat_with_others =
          Enum.map(packages, fn {name2, version2} ->
            if name1 == name2 do
              {name2, %{compatible: true, same_package: true}}
            else
              compatibility = check_package_compatibility(name1, version1, name2, version2)
              {name2, compatibility}
            end
          end)

        {name1,
         %{
           version: version1,
           elixir_compatible: compatible_with_elixir?(name1, version1, elixir_version),
           compatibility_with_others: Enum.into(compat_with_others, %{})
         }}
      end)

    %{
      matrix: Enum.into(compatibility_matrix, %{}),
      overall_compatibility: calculate_overall_compatibility(compatibility_matrix),
      elixir_version: elixir_version
    }
  end

  defp check_package_compatibility(_name1, _version1, _name2, _version2) do
    # Check if two package versions are compatible
    # This would check for known conflicts, dependency overlaps, etc.
    %{
      # Simplified - would need real compatibility checking
      compatible: true,
      conflicts: [],
      warnings: [],
      notes: []
    }
  end

  defp calculate_overall_compatibility(matrix) do
    # Calculate overall compatibility score
    total_checks =
      Enum.sum(
        Enum.map(matrix, fn {_name, data} ->
          map_size(data.compatibility_with_others)
        end)
      )

    compatible_checks =
      Enum.sum(
        Enum.map(matrix, fn {_name, data} ->
          Enum.count(data.compatibility_with_others, fn {_other, compat} ->
            compat.compatible
          end)
        end)
      )

    if total_checks > 0 do
      compatible_checks / total_checks
    else
      1.0
    end
  end

  defp generate_recommendations(compatibility_result) do
    # Generate recommendations based on compatibility analysis
    recommendations = []

    # Add recommendations based on compatibility score
    recommendations =
      if compatibility_result.overall_compatibility < 0.8 do
        ["Consider updating packages for better compatibility" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp extract_warnings(compatibility_result) do
    # Extract warnings from compatibility analysis
    elixir_warnings =
      Enum.flat_map(compatibility_result.matrix, fn {_name, data} ->
        if data.elixir_compatible do
          []
        else
          [
            "Package #{data.name} may not be compatible with Elixir #{compatibility_result.elixir_version}"
          ]
        end
      end)

    compat_warnings =
      Enum.flat_map(compatibility_result.matrix, fn {_name, data} ->
        Enum.flat_map(data.compatibility_with_others, fn {_other, compat} ->
          if compat.compatible do
            []
          else
            ["Potential incompatibility between packages"]
          end
        end)
      end)

    elixir_warnings ++ compat_warnings
  end

  defp get_package_checksum(name, version) do
    case Packages.get_release(name, version) do
      {:ok, release} -> release.checksum
      {:error, _} -> nil
    end
  end

  defp get_current_elixir_version do
    System.version()
  end

  @doc """
  Validate resolve dependencies arguments.
  """
  def validate_resolve_args(args) do
    required_fields = ["requirements"]
    optional_fields = ["elixir_version"]

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate dependency tree arguments.
  """
  def validate_tree_args(args) do
    required_fields = ["name", "version"]
    optional_fields = ["depth"]

    case validate_fields(args, required_fields, optional_fields) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate compatibility check arguments.
  """
  def validate_compatibility_args(args) do
    required_fields = ["packages"]
    optional_fields = ["elixir_version"]

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
  Get dependency resolution statistics for monitoring.
  """
  def get_dependency_stats do
    %{
      total_resolutions: get_total_resolutions_count(),
      avg_resolution_time: get_avg_resolution_time(),
      conflict_rate: get_conflict_rate(),
      most_common_packages: get_most_common_packages(),
      resolution_success_rate: get_resolution_success_rate()
    }
  end

  defp get_total_resolutions_count do
    # Get total dependency resolutions performed
    # This would require telemetry tracking
    0
  end

  defp get_avg_resolution_time do
    # Get average resolution time from telemetry
    0
  end

  defp get_conflict_rate do
    # Get rate of resolutions that result in conflicts
    0.0
  end

  defp get_most_common_packages do
    # Get most commonly resolved packages
    []
  end

  defp get_resolution_success_rate do
    # Get success rate of dependency resolutions
    1.0
  end

  @doc """
  Log dependency operation for telemetry.
  """
  def log_dependency_operation(operation, metadata \\ %{}) do
    :telemetry.execute(
      [:hex_hub, :mcp, :dependencies],
      %{
        operation: operation
      },
      metadata
    )
  end
end
