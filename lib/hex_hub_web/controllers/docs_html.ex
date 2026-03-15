defmodule HexHubWeb.DocsHTML do
  @moduledoc """
  View module for documentation pages.

  Parses the OpenAPI specification at compile time and provides helper functions
  for rendering API documentation.
  """
  use HexHubWeb, :html

  embed_templates "docs_html/*"

  @openapi_spec YamlElixir.read_from_file!("priv/static/openapi/hex-api.yaml")

  @doc """
  Returns the full OpenAPI specification map.
  """
  def openapi_spec, do: @openapi_spec

  @doc """
  Returns API metadata from the OpenAPI spec.
  """
  def api_info do
    info = @openapi_spec["info"]

    %{
      title: info["title"],
      version: info["version"],
      description: info["description"]
    }
  end

  @doc """
  Returns all API endpoints grouped by their OpenAPI tag.
  """
  def paths_by_tag do
    @openapi_spec["paths"]
    |> Enum.flat_map(fn {path, methods} ->
      methods
      |> Enum.reject(fn {k, _} -> k == "parameters" end)
      |> Enum.map(fn {method, spec} -> {path, method, spec} end)
    end)
    |> Enum.group_by(fn {_path, _method, spec} ->
      List.first(spec["tags"] || ["Other"])
    end)
    |> Enum.sort_by(fn {tag, _} -> tag end)
  end

  @doc """
  Returns list of all tags with their descriptions.
  """
  def tags do
    (@openapi_spec["tags"] || [])
    |> Enum.map(fn tag ->
      %{name: tag["name"], description: tag["description"]}
    end)
  end

  @doc """
  Returns Duskmoon-compatible badge color for HTTP method styling.
  """
  def method_color(method) do
    case String.downcase(method) do
      "get" -> "success"
      "post" -> "info"
      "put" -> "warning"
      "patch" -> "warning"
      "delete" -> "error"
      _ -> "secondary"
    end
  end

  @doc """
  Returns CSS classes for HTTP method badge styling.
  """
  def method_badge_class(method) do
    base =
      "inline-flex items-center px-2.5 py-1 rounded font-mono text-xs font-bold tracking-wider uppercase"

    color =
      case String.downcase(method) do
        "get" -> "bg-success/15 text-success"
        "post" -> "bg-info/15 text-info"
        "put" -> "bg-warning/15 text-warning"
        "patch" -> "bg-warning/15 text-warning"
        "delete" -> "bg-error/15 text-error"
        _ -> "bg-on-surface/10 text-on-surface-variant"
      end

    "#{base} #{color}"
  end

  @doc """
  Build example JSON-RPC request body for a tool.
  """
  def build_tool_example(tool) do
    example_args =
      case tool.input_schema do
        %{"properties" => props} when map_size(props) > 0 ->
          props
          |> Enum.sort_by(fn {name, _} ->
            if name in (tool.input_schema["required"] || []), do: "0_#{name}", else: "1_#{name}"
          end)
          |> Enum.into(%{}, fn {name, spec} ->
            {name, example_value_for_type(spec["type"], name)}
          end)

        _ ->
          %{}
      end

    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call/#{tool.name}",
      "params" => %{"arguments" => example_args}
    }
    |> Jason.encode!(pretty: true)
  end

  defp example_value_for_type("string", name) do
    cond do
      String.contains?(name, "name") -> "phoenix"
      String.contains?(name, "query") -> "web framework"
      String.contains?(name, "version") -> "1.7.0"
      String.contains?(name, "page") -> "index.html"
      String.contains?(name, "order") -> "desc"
      String.contains?(name, "sort") -> "name"
      String.contains?(name, "repository") -> "hexpm"
      true -> "example"
    end
  end

  defp example_value_for_type("integer", name) do
    cond do
      String.contains?(name, "page") -> 1
      String.contains?(name, "per_page") -> 20
      String.contains?(name, "limit") -> 10
      String.contains?(name, "depth") -> 3
      true -> 1
    end
  end

  defp example_value_for_type("boolean", _name), do: true
  defp example_value_for_type("array", _name), do: []
  defp example_value_for_type("object", _name), do: %{}
  defp example_value_for_type(_, _name), do: "example"

  @doc """
  Returns CSS classes for response status code badge.
  """
  def status_badge_class(code) do
    base = "inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold"

    color =
      cond do
        String.starts_with?(code, "2") -> "bg-success/15 text-success"
        String.starts_with?(code, "3") -> "bg-info/15 text-info"
        String.starts_with?(code, "4") -> "bg-warning/15 text-warning"
        String.starts_with?(code, "5") -> "bg-error/15 text-error"
        true -> "bg-on-surface/10 text-on-surface-variant"
      end

    "#{base} #{color}"
  end

  @doc """
  Returns navigation items for the documentation sidebar.
  """
  def nav_items do
    [
      %{page: :index, path: "/docs", label: "Overview", icon: "view-dashboard-outline"},
      %{
        page: :getting_started,
        path: "/docs/getting-started",
        label: "Getting Started",
        icon: "rocket-launch-outline"
      },
      %{
        page: :publishing,
        path: "/docs/publishing",
        label: "Publishing",
        icon: "package-variant-closed-plus"
      },
      %{
        page: :api_reference,
        path: "/docs/api-reference",
        label: "API Reference",
        icon: "code-braces"
      },
      %{page: :mcp, path: "/docs/mcp", label: "MCP Integration", icon: "robot-outline"}
    ]
  end

  @doc """
  Documentation layout component with sidebar navigation.
  """
  attr :current_page, :atom, required: true
  attr :page_title, :string, default: "Documentation"
  slot :inner_block, required: true

  def docs_layout(assigns) do
    ~H"""
    <div class="flex h-[calc(100dvh-5rem)] -m-4">
      <!-- Sidebar toggle (mobile) -->
      <input id="docs-drawer" type="checkbox" class="hidden peer" />
      <!-- Sidebar -->
      <aside class="hidden lg:flex flex-col w-72 shrink-0 bg-surface-container-low/80 backdrop-blur-sm border-r border-outline-variant/50 overflow-y-auto
                     peer-checked:flex peer-checked:fixed peer-checked:inset-0 peer-checked:z-40 peer-checked:w-72">
        <!-- Sidebar header -->
        <div class="sticky top-0 z-20 bg-surface-container-low/90 backdrop-blur-md border-b border-outline-variant/30">
          <a
            href="/docs"
            class="flex items-center gap-3 px-5 py-4 group"
          >
            <div class="w-9 h-9 bg-primary/15 rounded-xl flex items-center justify-center group-hover:bg-primary/25 transition-colors">
              <.dm_mdi name="book-open-page-variant" class="w-5 h-5" color="var(--color-primary)" />
            </div>
            <div>
              <span class="text-base font-bold text-on-surface tracking-tight">HexHub Docs</span>
            </div>
          </a>
        </div>
        <!-- Navigation -->
        <nav class="flex-1 px-3 py-4 space-y-1">
          <p class="px-3 pb-2 text-[0.65rem] font-bold uppercase tracking-[0.15em] text-on-surface-variant/60">
            Documentation
          </p>
          <%= for item <- nav_items() do %>
            <a
              href={item.path}
              class={[
                "group flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm transition-all duration-200",
                if(@current_page == item.page,
                  do: "bg-primary/12 text-primary font-semibold shadow-sm shadow-primary/5",
                  else:
                    "text-on-surface-variant hover:bg-surface-container-high hover:text-on-surface"
                )
              ]}
            >
              <.dm_mdi
                name={item.icon}
                class="w-[18px] h-[18px] shrink-0"
                color={
                  if(@current_page == item.page, do: "var(--color-primary)", else: "currentColor")
                }
              />
              <span>{item.label}</span>
              <%= if @current_page == item.page do %>
                <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary"></span>
              <% end %>
            </a>
          <% end %>
        </nav>
        <!-- Sidebar footer links -->
        <div class="border-t border-outline-variant/30 px-3 py-3 space-y-1">
          <a
            href="/openapi/hex-api.yaml"
            target="_blank"
            class="flex items-center gap-3 px-3 py-2 rounded-xl text-sm text-on-surface-variant hover:bg-surface-container-high hover:text-on-surface transition-colors"
          >
            <.dm_mdi name="file-download-outline" class="w-[18px] h-[18px]" />
            <span>OpenAPI Spec</span>
            <.dm_mdi name="open-in-new" class="w-3.5 h-3.5 ml-auto opacity-40" />
          </a>
          <a
            href="/"
            class="flex items-center gap-3 px-3 py-2 rounded-xl text-sm text-on-surface-variant hover:bg-surface-container-high hover:text-on-surface transition-colors"
          >
            <.dm_mdi name="arrow-left" class="w-[18px] h-[18px]" />
            <span>Back to Home</span>
          </a>
        </div>
      </aside>
      <!-- Mobile sidebar backdrop -->
      <label
        for="docs-drawer"
        class="hidden peer-checked:block fixed inset-0 z-30 bg-black/40 backdrop-blur-sm"
        aria-label="close sidebar"
      >
      </label>
      <!-- Main content -->
      <div class="flex-1 overflow-y-auto scroll-smooth">
        <!-- Mobile menu button -->
        <div class="lg:hidden sticky top-0 z-20 flex h-14 items-center gap-3 bg-surface/85 backdrop-blur-md px-4 border-b border-outline-variant/50">
          <label
            for="docs-drawer"
            class="cursor-pointer p-2 -ml-2 rounded-xl hover:bg-surface-container-high transition-colors"
          >
            <.dm_mdi name="menu" class="w-5 h-5" />
          </label>
          <span class="font-semibold text-on-surface">{@page_title}</span>
        </div>
        <!-- Page content -->
        <div class="p-6 lg:px-12 lg:py-10 max-w-4xl">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a styled code block with a label and monospace content.
  """
  attr :label, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def code_block(assigns) do
    ~H"""
    <div class={[
      "group relative rounded-xl overflow-hidden border border-outline-variant/40 mb-6",
      @class
    ]}>
      <%= if @label do %>
        <div class="flex items-center gap-2 px-4 py-2 bg-surface-container-high/60 border-b border-outline-variant/30">
          <.dm_mdi name="file-code-outline" class="w-3.5 h-3.5 text-on-surface-variant/60" />
          <span class="text-xs font-medium text-on-surface-variant/70 tracking-wide">{@label}</span>
        </div>
      <% end %>
      <div class="bg-surface-container-high/40 p-4 font-mono text-sm leading-relaxed overflow-x-auto">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an info/warning callout box.
  """
  attr :type, :string, default: "info"
  attr :title, :string, required: true
  slot :inner_block, required: true

  def callout(assigns) do
    {icon, color_classes} =
      case assigns.type do
        "warning" ->
          {"alert-outline", "border-warning/30 bg-warning/5"}

        "error" ->
          {"alert-circle-outline", "border-error/30 bg-error/5"}

        _ ->
          {"information-outline", "border-info/30 bg-info/5"}
      end

    assigns = assign(assigns, icon: icon, color_classes: color_classes)

    ~H"""
    <div class={["flex gap-4 p-4 rounded-xl border mb-6", @color_classes]}>
      <div class="shrink-0 mt-0.5">
        <.dm_mdi
          name={@icon}
          class="w-5 h-5"
          color={
            case @type do
              "warning" -> "var(--color-warning)"
              "error" -> "var(--color-error)"
              _ -> "var(--color-info)"
            end
          }
        />
      </div>
      <div class="min-w-0">
        <p class="font-semibold text-sm text-on-surface mb-1">{@title}</p>
        <div class="text-sm text-on-surface-variant leading-relaxed">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Section heading with anchor link.
  """
  attr :id, :string, required: true
  attr :level, :integer, default: 2
  slot :inner_block, required: true

  def section_heading(assigns) do
    ~H"""
    <h2
      :if={@level == 2}
      id={@id}
      class="group text-2xl font-bold text-on-surface mt-12 mb-4 scroll-mt-24 flex items-center gap-2"
    >
      {render_slot(@inner_block)}
      <a
        href={"##{@id}"}
        class="opacity-0 group-hover:opacity-40 transition-opacity text-on-surface-variant"
      >
        <.dm_mdi name="link-variant" class="w-5 h-5" />
      </a>
    </h2>
    <h3
      :if={@level == 3}
      id={@id}
      class="group text-lg font-semibold text-on-surface mt-8 mb-3 scroll-mt-24 flex items-center gap-2"
    >
      {render_slot(@inner_block)}
      <a
        href={"##{@id}"}
        class="opacity-0 group-hover:opacity-40 transition-opacity text-on-surface-variant"
      >
        <.dm_mdi name="link-variant" class="w-4 h-4" />
      </a>
    </h3>
    """
  end
end
