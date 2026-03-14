defmodule HexHubWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HexHubWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-50">
      <nav class="navbar navbar-surface-container-high border-b border-outline-variant">
        <div class="max-w-7xl mx-auto w-full flex items-center justify-between px-4 sm:px-6">
          <div class="flex items-center gap-8">
            <a
              href="/"
              class="flex items-center gap-2 text-xl font-bold text-primary hover:opacity-80 transition-opacity"
            >
              <.dm_mdi name="hexagon-multiple" class="w-7 h-7" color="var(--color-primary)" /> HexHub
            </a>
            <div class="hidden sm:flex items-center gap-1">
              <a
                href="/packages"
                class="navbar-item px-3 py-2 rounded-lg text-sm font-medium text-on-surface-variant hover:text-on-surface hover:bg-surface-container transition-colors"
              >
                Packages
              </a>
              <a
                href="/docs"
                class="navbar-item px-3 py-2 rounded-lg text-sm font-medium text-on-surface-variant hover:text-on-surface hover:bg-surface-container transition-colors"
              >
                Docs
              </a>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <.dm_theme_switcher />
            <.dm_link
              href="https://github.com/gsmlg-dev/hex_hub"
              class="p-2 rounded-lg hover:bg-surface-container transition-colors"
            >
              <.dm_mdi name="github" class="w-6 h-6" />
            </.dm_link>
          </div>
        </div>
      </nav>
    </header>

    <main class="min-h-[calc(100dvh-8rem)]">
      {render_slot(@inner_block)}
    </main>

    <footer class="border-t border-outline-variant bg-surface-container-low">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 py-8">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-on-surface-variant">
          <p>HexHub &mdash; Private Hex Package Manager</p>
          <div class="flex items-center gap-4">
            <a href="/docs" class="hover:text-on-surface transition-colors">Documentation</a>
            <a href="/docs/api-reference" class="hover:text-on-surface transition-colors">API</a>
            <a
              href="https://github.com/gsmlg-dev/hex_hub"
              class="hover:text-on-surface transition-colors"
            >
              GitHub
            </a>
          </div>
        </div>
      </div>
    </footer>

    <.dm_flash_group flash={@flash} />
    """
  end
end
