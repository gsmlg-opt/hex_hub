defmodule HexHubWeb.DocsController do
  @moduledoc """
  Controller for documentation pages.

  Handles rendering of Getting Started, Publishing, and API Reference documentation.
  """
  use HexHubWeb, :controller

  def index(conn, _params) do
    emit_page_view_telemetry(:index)
    render(conn, :index, page_title: "Documentation", current_page: :index)
  end

  def getting_started(conn, _params) do
    emit_page_view_telemetry(:getting_started)

    render(conn, :getting_started,
      page_title: "Getting Started",
      current_page: :getting_started,
      hex_hub_url: HexHubWeb.PageHTML.hex_hub_url(conn)
    )
  end

  def publishing(conn, _params) do
    emit_page_view_telemetry(:publishing)

    render(conn, :publishing,
      page_title: "Publishing Packages",
      current_page: :publishing,
      hex_hub_api_url: HexHubWeb.PageHTML.hex_hub_api_url(conn)
    )
  end

  def api_reference(conn, _params) do
    emit_page_view_telemetry(:api_reference)

    render(conn, :api_reference,
      page_title: "API Reference",
      current_page: :api_reference,
      endpoints_by_tag: HexHubWeb.DocsHTML.paths_by_tag(),
      api_info: HexHubWeb.DocsHTML.api_info()
    )
  end

  def mcp(conn, _params) do
    emit_page_view_telemetry(:mcp)

    mcp_url = "#{conn.scheme}://#{conn.host}:#{conn.port}/mcp"

    # Build tool specs directly from the Tools module for docs display
    tools = HexHub.MCP.Tools.register_all_tools()

    tool_specs =
      tools
      |> Enum.map(fn {name, tool} ->
        %{
          name: name,
          description: tool.description,
          input_schema: tool.input_schema
        }
      end)
      |> Enum.sort_by(& &1.name)

    # Group tools by category
    tool_groups = [
      %{
        name: "Package Management",
        icon: "package-variant",
        color: "primary",
        tools: Enum.filter(tool_specs, &(&1.name in ~w(search_packages get_package list_packages get_package_metadata)))
      },
      %{
        name: "Release Management",
        icon: "source-branch",
        color: "secondary",
        tools: Enum.filter(tool_specs, &(&1.name in ~w(list_releases get_release download_release compare_releases)))
      },
      %{
        name: "Documentation Access",
        icon: "file-document-outline",
        color: "tertiary",
        tools: Enum.filter(tool_specs, &(&1.name in ~w(get_documentation list_documentation_versions search_documentation)))
      },
      %{
        name: "Dependency Resolution",
        icon: "graph-outline",
        color: "info",
        tools: Enum.filter(tool_specs, &(&1.name in ~w(resolve_dependencies get_dependency_tree check_compatibility)))
      },
      %{
        name: "Repository Management",
        icon: "database-cog-outline",
        color: "warning",
        tools: Enum.filter(tool_specs, &(&1.name in ~w(list_repositories get_repository_info toggle_package_visibility)))
      }
    ]

    render(conn, :mcp,
      page_title: "MCP Integration",
      current_page: :mcp,
      mcp_url: mcp_url,
      tool_groups: tool_groups,
      tool_count: length(tool_specs)
    )
  end

  # Emit telemetry event for documentation page views (Constitution Principle VII)
  defp emit_page_view_telemetry(page) do
    :telemetry.execute(
      [:hex_hub, :docs, :page_view],
      %{count: 1},
      %{page: page}
    )
  end
end
