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
  Returns DaisyUI badge classes for HTTP method styling.
  """
  def method_badge_class(method) do
    case String.downcase(method) do
      "get" -> "badge badge-success"
      "post" -> "badge badge-info"
      "put" -> "badge badge-warning"
      "patch" -> "badge badge-warning"
      "delete" -> "badge badge-error"
      _ -> "badge badge-neutral"
    end
  end

  @doc """
  Returns navigation items for the documentation sidebar.
  """
  def nav_items do
    [
      %{page: :index, path: "/docs", label: "Overview"},
      %{page: :getting_started, path: "/docs/getting-started", label: "Getting Started"},
      %{page: :publishing, path: "/docs/publishing", label: "Publishing"},
      %{page: :api_reference, path: "/docs/api-reference", label: "API Reference"}
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
      <aside class="hidden lg:flex flex-col w-64 shrink-0 bg-surface-container-low border-r border-outline-variant overflow-y-auto
                     peer-checked:flex peer-checked:fixed peer-checked:inset-0 peer-checked:z-40 peer-checked:w-64">
        <div class="sticky top-0 z-20 bg-surface-container-low backdrop-blur">
          <a href="/docs" class="flex items-center gap-2 px-4 py-3 text-xl font-semibold hover:opacity-80">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M12 6.042A8.967 8.967 0 006 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 016 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 016-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0018 18a8.967 8.967 0 00-6 2.292m0-14.25v14.25"
              />
            </svg>
            HexHub Docs
          </a>
        </div>
        <nav class="flex flex-col gap-1 px-3 py-2">
          <%= for item <- nav_items() do %>
            <a
              href={item.path}
              class={[
                "px-3 py-2 rounded-lg text-sm transition-colors",
                if(@current_page == item.page,
                  do: "bg-primary/15 text-primary font-semibold",
                  else: "hover:bg-surface-container-high"
                )
              ]}
            >
              {item.label}
            </a>
          <% end %>
        </nav>
        <div class="border-t border-outline-variant mx-3 my-2"></div>
        <nav class="flex flex-col gap-1 px-3 py-2">
          <a
            href="/openapi/hex-api.yaml"
            target="_blank"
            class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm hover:bg-surface-container-high"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-4 h-4"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3"
              />
            </svg>
            OpenAPI Spec (YAML)
          </a>
          <a
            href="/"
            class="flex items-center gap-2 px-3 py-2 rounded-lg text-sm hover:bg-surface-container-high"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-4 h-4"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M2.25 12l8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"
              />
            </svg>
            Back to Home
          </a>
        </nav>
      </aside>
      <!-- Mobile sidebar backdrop -->
      <label
        for="docs-drawer"
        class="hidden peer-checked:block fixed inset-0 z-30 bg-black/50"
        aria-label="close sidebar"
      >
      </label>
      <!-- Main content -->
      <div class="flex-1 overflow-y-auto">
        <!-- Mobile menu button -->
        <div class="lg:hidden sticky top-0 z-20 flex h-14 items-center gap-2 bg-surface/90 backdrop-blur px-4 border-b border-outline-variant">
          <label for="docs-drawer" class="cursor-pointer p-2 rounded-lg hover:bg-surface-container-high">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="w-6 h-6 stroke-current"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 6h16M4 12h16M4 18h16"
              >
              </path>
            </svg>
          </label>
          <span class="font-bold text-lg">{@page_title}</span>
        </div>
        <!-- Page content -->
        <div class="p-6 lg:p-8">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
end
