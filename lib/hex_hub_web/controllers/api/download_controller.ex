defmodule HexHubWeb.API.DownloadController do
  use HexHubWeb, :controller

  alias HexHub.Packages

  action_fallback HexHubWeb.FallbackController

  @doc """
  Download package tarball with upstream fallback.
  """
  def package(conn, %{"name" => name, "version" => version}) do
    start_time = System.monotonic_time()

    case Packages.download_package_with_upstream(name, version) do
      {:ok, tarball} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("downloads.package", duration_ms, 200)

        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{name}-#{version}.tar\""
        )
        # 1 year cache
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_resp(200, tarball)

      {:error, _reason} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("downloads.package", duration_ms, 404, "not_found")

        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})
    end
  end

  @doc """
  Download tarball for Mix HEX_MIRROR compatibility.
  Parses tarball name in format "package-name-version.tar" and redirects to package download.
  """
  def tarball(conn, %{"tarball" => tarball_name}) do
    start_time = System.monotonic_time()

    # Parse tarball name to extract package name and version
    # Format: package-name-version.tar
    case parse_tarball_name(tarball_name) do
      {:ok, name, version} ->
        case Packages.download_package_with_upstream(name, version) do
          {:ok, tarball} ->
            duration_ms =
              (System.monotonic_time() - start_time)
              |> System.convert_time_unit(:native, :millisecond)

            HexHub.Telemetry.track_api_request("downloads.tarball", duration_ms, 200)

            conn
            |> put_resp_content_type("application/octet-stream")
            |> put_resp_header(
              "content-disposition",
              "attachment; filename=\"#{tarball_name}\""
            )
            # 1 year cache
            |> put_resp_header("cache-control", "public, max-age=31536000")
            |> send_resp(200, tarball)

          {:error, _reason} ->
            duration_ms =
              (System.monotonic_time() - start_time)
              |> System.convert_time_unit(:native, :millisecond)

            HexHub.Telemetry.track_api_request("downloads.tarball", duration_ms, 404, "not_found")

            conn
            |> put_status(:not_found)
            |> json(%{message: "Package not found"})
        end

      {:error, _reason} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request(
          "downloads.tarball",
          duration_ms,
          400,
          "invalid_tarball"
        )

        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid tarball format"})
    end
  end

  @doc """
  Download documentation tarball with upstream fallback.
  """
  def docs(conn, %{"name" => name, "version" => version}) do
    start_time = System.monotonic_time()

    case Packages.download_docs_with_upstream(name, version) do
      {:ok, docs_tarball} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("downloads.docs", duration_ms, 200)

        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{name}-#{version}-docs.tar\""
        )
        # 1 year cache
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_resp(200, docs_tarball)

      {:error, _reason} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("downloads.docs", duration_ms, 404, "not_found")

        conn
        |> put_status(:not_found)
        |> json(%{message: "Documentation not found"})
    end
  end

  # Private helper functions

  defp parse_tarball_name(tarball_name) do
    # Remove .tar extension if present
    base_name = String.replace_suffix(tarball_name, ".tar", "")

    # Match package name followed by a semver version (starts with digit.digit)
    # This correctly handles pre-release versions like "phoenix_duskmoon-9.0.0-rc.3"
    case Regex.run(~r/^(.+?)-(\d+\..+)$/, base_name) do
      [_, package_name, version] ->
        {:ok, package_name, version}

      _ ->
        # No match, invalid format
        {:error, :invalid_format}
    end
  end
end
