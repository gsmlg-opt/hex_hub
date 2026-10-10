defmodule HexHubAdminWeb.Layouts do
  @moduledoc """
  Layout components for the admin web interface.
  """
  use HexHubAdminWeb, :html

  import HexHubWeb.VersionBadge, only: [version_badge: 1]

  embed_templates "layouts/*"

  @app_version Mix.Project.config()[:version]

  def app_version, do: @app_version
end
