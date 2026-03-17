defmodule HexHubWeb.BadgeController do
  use HexHubWeb, :controller

  alias HexHub.Packages

  @doc """
  Serves an SVG badge showing the package name and latest version.

  Usage in GitHub markdown:
      ![package](https://your-hex-hub.com/packages/:name/badge.svg)
  """
  def show(conn, %{"name" => name}) do
    {label, version, color} = badge_info(name)

    svg = render_badge(label, version, color)

    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, svg)
  end

  defp badge_info(name) do
    case Packages.get_package(name) do
      {:ok, _package} ->
        case Packages.list_releases(name) do
          {:ok, releases} when releases != [] ->
            latest =
              releases
              |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
              |> List.first()

            {name, latest.version, "#6e4a7e"}

          _ ->
            {name, "no releases", "#999"}
        end

      {:error, _} ->
        {name, "not found", "#e05d44"}
    end
  end

  defp render_badge(label, version, color) do
    label_width = String.length(label) * 6.5 + 10
    version_width = String.length(version) * 6.5 + 10
    total_width = label_width + version_width

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{round(total_width)}" height="20" role="img" aria-label="#{label}: #{version}">
      <title>#{label}: #{version}</title>
      <linearGradient id="s" x2="0" y2="100%">
        <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
        <stop offset="1" stop-opacity=".1"/>
      </linearGradient>
      <clipPath id="r">
        <rect width="#{round(total_width)}" height="20" rx="3" fill="#fff"/>
      </clipPath>
      <g clip-path="url(#r)">
        <rect width="#{round(label_width)}" height="20" fill="#555"/>
        <rect x="#{round(label_width)}" width="#{round(version_width)}" height="20" fill="#{color}"/>
        <rect width="#{round(total_width)}" height="20" fill="url(#s)"/>
      </g>
      <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="11">
        <text aria-hidden="true" x="#{round(label_width / 2)}" y="15" fill="#010101" fill-opacity=".3">#{escape(label)}</text>
        <text x="#{round(label_width / 2)}" y="14">#{escape(label)}</text>
        <text aria-hidden="true" x="#{round(label_width + version_width / 2)}" y="15" fill="#010101" fill-opacity=".3">#{escape(version)}</text>
        <text x="#{round(label_width + version_width / 2)}" y="14">#{escape(version)}</text>
      </g>
    </svg>
    """
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
