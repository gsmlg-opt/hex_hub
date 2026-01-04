defmodule HexHubAdminWeb.BackupHTML do
  @moduledoc """
  HTML helpers for backup management views.
  """
  use HexHubAdminWeb, :html

  embed_templates "backup_html/*"

  @doc """
  Formats a backup status for display.
  """
  def format_status(:pending), do: {"Pending", "badge-warning"}
  def format_status(:completed), do: {"Completed", "badge-success"}
  def format_status(:failed), do: {"Failed", "badge-error"}
  def format_status(_), do: {"Unknown", "badge-ghost"}

  @doc """
  Formats file size for human-readable display.
  """
  def format_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_size(_), do: "N/A"

  @doc """
  Formats a datetime for display.
  """
  def format_datetime(nil), do: "N/A"

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_datetime(_), do: "N/A"

  @doc """
  Formats relative time (e.g., "2 hours ago").
  """
  def format_relative(nil), do: "N/A"

  def format_relative(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 2_592_000 -> "#{div(diff, 86400)} days ago"
      true -> format_datetime(dt)
    end
  end

  def format_relative(_), do: "N/A"
end
