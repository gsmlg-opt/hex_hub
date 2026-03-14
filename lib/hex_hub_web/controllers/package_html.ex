defmodule HexHubWeb.PackageHTML do
  use HexHubWeb, :html

  embed_templates "package_html/*"

  @doc """
  Format a datetime as a date string.
  """
  def format_date(datetime) do
    datetime
    |> NaiveDateTime.to_date()
    |> Date.to_string()
  end

  @doc """
  Format a datetime as a relative time string (e.g., "2 days ago").
  """
  def format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      diff < 2_592_000 -> "#{div(diff, 604_800)} weeks ago"
      diff < 31_536_000 -> "#{div(diff, 2_592_000)} months ago"
      true -> "#{div(diff, 31_536_000)} years ago"
    end
  end

  @doc """
  Format description with truncation.
  """
  def format_description(description) do
    if String.length(description) > 120 do
      String.slice(description, 0, 117) <> "..."
    else
      description
    end
  end

  @doc """
  Format downloads count (e.g., 1.5M, 100K).
  """
  def format_downloads(nil), do: "N/A"
  def format_downloads(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  def format_downloads(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  def format_downloads(n), do: to_string(n)

  @doc """
  Generate pagination link preserving current query params.
  """
  def pagination_link(assigns, page) do
    query_params = preserve_params(assigns, %{page: page})
    path = "/packages?" <> URI.encode_query(query_params)
    path
  end

  @doc """
  Preserve current query params and merge with updates.
  """
  def preserve_params(assigns, updates) do
    base = %{}
    base = if assigns[:search], do: Map.put(base, :search, assigns[:search]), else: base

    base =
      if assigns[:sort] && assigns[:sort] != :recent_downloads,
        do: Map.put(base, :sort, assigns[:sort]),
        else: base

    base = if assigns[:letter], do: Map.put(base, :letter, assigns[:letter]), else: base

    Map.merge(base, updates)
  end

  @doc """
  Generate page range for pagination.
  """
  def page_range(current, total, window \\ 2) do
    start_page = max(1, current - window)
    end_page = min(total, current + window)
    Enum.to_list(start_page..end_page)
  end

  @doc """
  Get license name from package metadata.
  """
  def license_name(package) do
    case package.meta["licenses"] do
      [license | _] -> license
      _ -> "Unknown"
    end
  end

  @doc """
  Generate version badge HTML.
  """
  def package_badge(%{latest_version: version}) do
    "<span class=\"badge badge-primary badge-sm\">v#{version}</span>"
  end

  @doc """
  Generate download count badge HTML.
  """
  def download_count_badge(count) do
    formatted_count = format_downloads(count)
    "<span class=\"badge badge-ghost badge-sm\">#{formatted_count}</span>"
  end

  @doc """
  Build sort option URL.
  """
  def sort_url(assigns, sort) do
    query_params = preserve_params(assigns, %{sort: sort, page: 1})
    "/packages?" <> URI.encode_query(query_params)
  end

  @doc """
  Build letter filter URL.
  """
  def letter_url(assigns, letter) do
    query_params = preserve_params(assigns, %{letter: letter, page: 1})
    # Remove letter key if it's nil/empty
    query_params =
      if letter in [nil, ""], do: Map.delete(query_params, :letter), else: query_params

    "/packages?" <> URI.encode_query(query_params)
  end

  @doc """
  Get sort option label for display.
  """
  def sort_label(sort) do
    case sort do
      :recent_downloads -> "Recent Downloads"
      :total_downloads -> "Total Downloads"
      :name -> "Name (A-Z)"
      :recently_updated -> "Recently Updated"
      :recently_created -> "Recently Created"
      _ -> "Recent Downloads"
    end
  end

  @doc """
  Build URL pattern for dm_pagination component.
  Uses {page} as the placeholder that dm_pagination replaces with the actual page number.
  """
  def pagination_url_pattern(assigns) do
    query_params = preserve_params(assigns, %{page: "{page}"})
    "/packages?" <> URI.encode_query(query_params)
  end
end
