defmodule HexHubWeb.PackageController do
  use HexHubWeb, :controller
  alias HexHub.Packages

  @per_page 30
  @valid_sorts ~w(recent_downloads total_downloads name recently_updated recently_created)

  def index(conn, params) do
    page = parse_int(params["page"], 1)
    search = params["search"]
    sort = parse_sort(params["sort"])
    letter = parse_letter(params["letter"])

    has_filter = (search && search != "") || letter != nil

    {packages, total_count, total_pages} =
      if has_filter do
        opts = [
          page: page,
          per_page: @per_page,
          search: search,
          sort: sort,
          letter: letter
        ]

        case Packages.list_packages(opts) do
          {:ok, pkgs, total} ->
            enriched = Enum.map(pkgs, &enrich_package_with_latest_version/1)
            {enriched, total, max(1, ceil(total / @per_page))}

          _ ->
            {[], 0, 1}
        end
      else
        {[], 0, 1}
      end

    # Fetch trend data for the discovery section
    most_downloaded =
      Packages.list_most_downloaded(10) |> Enum.map(&enrich_package_with_latest_version/1)

    recently_updated =
      Packages.list_recently_updated(10) |> Enum.map(&enrich_package_with_latest_version/1)

    new_packages =
      Packages.list_new_packages(10) |> Enum.map(&enrich_package_with_latest_version/1)

    render(conn, :index,
      packages: packages,
      page: page,
      per_page: @per_page,
      total_count: total_count,
      total_pages: total_pages,
      search: search,
      sort: sort,
      letter: letter,
      has_filter: has_filter,
      most_downloaded: most_downloaded,
      recently_updated: recently_updated,
      new_packages: new_packages
    )
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_sort(nil), do: :recent_downloads

  defp parse_sort(sort) when sort in @valid_sorts do
    String.to_existing_atom(sort)
  end

  defp parse_sort(_), do: :recent_downloads

  defp parse_letter(nil), do: nil
  defp parse_letter(""), do: nil

  defp parse_letter(letter) when is_binary(letter) do
    letter = String.upcase(String.first(letter))
    if letter =~ ~r/^[A-Z]$/, do: letter, else: nil
  end

  def show(conn, %{"name" => name} = params) do
    # Check Accept header to determine if this is a browser request or registry request
    # Registry requests (from Hex client via HEX_MIRROR) don't have Accept: text/html
    accept_header = Plug.Conn.get_req_header(conn, "accept")

    if wants_html?(accept_header) do
      show_html(conn, name)
    else
      # Forward to registry controller for protobuf response
      HexHubWeb.API.RegistryController.package(conn, params)
    end
  end

  defp wants_html?([]), do: false

  defp wants_html?([accept | _]) do
    # Check if Accept header explicitly asks for HTML
    String.contains?(accept, "text/html")
  end

  defp show_html(conn, name) do
    start_time = System.monotonic_time()

    case Packages.get_package(name) do
      {:ok, package} ->
        {:ok, releases} = Packages.list_releases(name)
        enriched_package = enrich_package_with_latest_version(package)

        # Sort releases by version descending
        sorted_releases = Enum.sort_by(releases, & &1.version, {:desc, Version})

        latest_version = get_latest_version(sorted_releases)
        dependencies = get_dependencies(sorted_releases)
        download_stats = get_download_stats(package, sorted_releases)

        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        :telemetry.execute(
          [:hex_hub, :packages, :view],
          %{duration: duration_ms},
          %{package: name}
        )

        render(conn, :show,
          package: enriched_package,
          releases: sorted_releases,
          latest_version: latest_version,
          dependencies: dependencies,
          download_stats: download_stats
        )

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> assign(:name, name)
        |> render(:not_found)
    end
  end

  defp get_latest_version([]), do: "0.0.0"
  defp get_latest_version([release | _]), do: release.version

  defp get_dependencies([]), do: %{}

  defp get_dependencies([latest_release | _]) do
    case latest_release.requirements do
      reqs when is_map(reqs) -> reqs
      _ -> %{}
    end
  end

  defp get_download_stats(package, releases) do
    total = package.downloads
    # Sum up release downloads for "recent" approximation
    recent = Enum.reduce(releases, 0, fn r, acc -> acc + r.downloads end)

    %{
      total: total,
      recent: recent,
      # Would need additional tracking for accurate weekly stats
      weekly: nil
    }
  end

  def docs(conn, %{"name" => name} = params) do
    {version, page} = extract_docs_version_and_page(params)

    # Redirect to trailing slash so relative links in docs HTML resolve correctly
    if is_nil(page) and not String.ends_with?(conn.request_path, "/") do
      redirect(conn, to: conn.request_path <> "/")
    else
      case resolve_docs_version(name, version) do
        {:ok, resolved_version} ->
          serve_docs_page(conn, name, resolved_version, page || "index.html")

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> put_view(HexHubWeb.ErrorHTML)
          |> render(:"404", message: "Documentation not found for #{name}")
      end
    end
  end

  defp extract_docs_version_and_page(params) do
    version = params["version"]

    page =
      case params["page"] do
        nil ->
          nil

        list when is_list(list) ->
          joined = Enum.join(list, "/")
          if joined == "", do: nil, else: joined

        str when is_binary(str) ->
          if str == "", do: nil, else: str
      end

    {version, page}
  end

  defp resolve_docs_version(name, nil) do
    case Packages.list_releases(name) do
      {:ok, releases} ->
        sorted = Enum.sort_by(releases, & &1.version, {:desc, Version})

        case Enum.find(sorted, & &1.has_docs) do
          nil ->
            # No release has docs locally, try the latest version (upstream may have docs)
            case sorted do
              [latest | _] -> {:ok, latest.version}
              [] -> {:error, :not_found}
            end

          release ->
            {:ok, release.version}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_docs_version(name, version) do
    case Packages.get_release(name, version) do
      {:ok, release} -> {:ok, release.version}
      _ -> {:error, :not_found}
    end
  end

  defp serve_docs_page(conn, name, version, page) do
    case Packages.download_docs_with_upstream(name, version) do
      {:ok, docs_tarball} ->
        case extract_file_from_docs_tarball(docs_tarball, page) do
          {:ok, content} ->
            conn
            |> put_resp_content_type(mime_type_for(page))
            |> put_layout(false)
            |> send_resp(200, content)

          {:error, :not_found} ->
            send_docs_404(conn, "Page #{page} not found in documentation for #{name}")
        end

      {:error, _reason} ->
        send_docs_404(conn, "Documentation not found for #{name}")
    end
  end

  defp send_docs_404(conn, message) do
    html = """
    <!DOCTYPE html>
    <html><head><title>Not Found</title>
    <style>body{font-family:system-ui;display:flex;justify-content:center;align-items:center;min-height:80vh;color:#555}
    .c{text-align:center}h1{font-size:3rem;color:#ccc}p{margin-top:1rem}a{color:#6366f1}</style>
    </head><body><div class="c"><h1>404</h1><p>#{message}</p><p><a href="/packages">Browse packages</a></p></div></body></html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, html)
  end

  defp extract_file_from_docs_tarball(tarball_data, target_file) do
    case :erl_tar.extract({:binary, tarball_data}, [:memory, :compressed]) do
      {:ok, files} ->
        case Enum.find(files, fn {path, _content} ->
               to_string(path) == target_file
             end) do
          {_path, content} -> {:ok, content}
          nil -> {:error, :not_found}
        end

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  defp mime_type_for(path) do
    case Path.extname(path) do
      ".html" -> "text/html"
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".json" -> "application/json"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      ".woff" -> "font/woff"
      ".woff2" -> "font/woff2"
      ".ttf" -> "font/ttf"
      ".eot" -> "application/vnd.ms-fontobject"
      ".ico" -> "image/x-icon"
      _ -> "application/octet-stream"
    end
  end

  def redirect_to_packages(conn, _params) do
    redirect(conn, to: ~p"/packages")
  end

  def redirect_to_package(conn, %{"name" => name}) do
    redirect(conn, to: ~p"/packages/#{name}")
  end

  defp enrich_package_with_latest_version(package) do
    {:ok, releases} = Packages.list_releases(package.name)

    latest_version =
      case releases do
        [] ->
          "0.0.0"

        releases ->
          releases
          |> Enum.map(& &1.version)
          |> Enum.sort_by(& &1, &>=/2)
          |> List.first()
      end

    Map.put(package, :latest_version, latest_version)
  end
end
