defmodule HexHubWeb.VersionBadge do
  @moduledoc """
  Shared appbar version badge and build details.
  """
  use Phoenix.Component

  import PhoenixDuskmoon.Component.DataDisplay.Badge, only: [dm_badge: 1]
  import PhoenixDuskmoon.Component.DataDisplay.Tooltip, only: [dm_tooltip: 1]

  attr :id, :string, required: true

  def version_badge(assigns) do
    info = HexHub.BuildInfo.info()
    version = "v#{info.version}#{if info.development, do: "-dev", else: ""}"

    release_time =
      if info.development,
        do: "Not released (development)",
        else: info.released_at || "Not recorded"

    details =
      Enum.join(
        [
          "Version: #{version}",
          "Mode: #{info.environment}",
          "Git ref: #{info.git_ref || "Unknown"}",
          "Commit: #{info.git_sha || "Unknown"}",
          "Release time: #{release_time}",
          "Build time: #{info.built_at}"
        ],
        "\n"
      )

    assigns = assign(assigns, version: version, details: details)

    ~H"""
    <.dm_tooltip
      :let={trigger_attrs}
      id={@id}
      content={@details}
      position="bottom"
      class="app-version-tooltip"
    >
      <button
        type="button"
        aria-label={"Version details for #{@version}"}
        class="inline-flex shrink-0 cursor-help rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        {trigger_attrs}
      >
        <.dm_badge variant="secondary" pill class="font-medium whitespace-nowrap">
          {@version}
        </.dm_badge>
      </button>
    </.dm_tooltip>
    """
  end
end
