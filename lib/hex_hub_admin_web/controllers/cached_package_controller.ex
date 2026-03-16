defmodule HexHubAdminWeb.CachedPackageController do
  @moduledoc """
  Controller for managing cached packages from upstream in the admin interface.
  """
  use HexHubAdminWeb, :controller

  alias HexHub.CachedPackages
  alias HexHub.Packages

  @doc """
  Lists all cached packages with pagination, search, and sorting.
  """
  def index(conn, params) do
    start_time = System.monotonic_time()

    opts = [
      page: parse_int(params["page"], 1),
      per_page: parse_int(params["per_page"], 50) |> min(100),
      search: params["search"],
      sort: parse_sort(params["sort"]),
      sort_dir: parse_sort_dir(params["sort_dir"])
    ]

    case CachedPackages.list_packages_by_source(:cached, opts) do
      {:ok, %{packages: packages, pagination: pagination}} ->
        # Emit telemetry event
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:hex_hub, :admin, :cached_packages, :listed],
          %{duration: duration},
          %{page: opts[:page], count: length(packages), search: opts[:search]}
        )

        render(conn, :index,
          packages: packages,
          pagination: pagination,
          search: params["search"] || "",
          sort: to_string(opts[:sort]),
          sort_dir: to_string(opts[:sort_dir])
        )

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to load packages")
        |> render(:index,
          packages: [],
          pagination: %{page: 1, per_page: 50, total: 0, total_pages: 1},
          search: "",
          sort: "updated_at",
          sort_dir: "desc"
        )
    end
  end

  @doc """
  Shows details for a specific cached package.
  """
  @dialyzer {:nowarn_function, show: 2}
  def show(conn, %{"id" => name}) do
    case CachedPackages.get_package_by_source(name, :cached) do
      {:ok, package} ->
        {:ok, releases} = Packages.list_releases(name)
        is_shadowed = CachedPackages.has_local_counterpart?(name)

        # Get local package details if shadowed
        local_package =
          if is_shadowed do
            case CachedPackages.get_package_by_source(name, :local) do
              {:ok, pkg} -> pkg
              _ -> nil
            end
          else
            nil
          end

        render(conn, :show,
          package: package,
          releases: releases,
          is_shadowed: is_shadowed,
          local_package: local_package
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Package not found or not a cached package")
        |> redirect(to: ~p"/cached-packages")
    end
  end

  @doc """
  Deletes a single cached package.
  """
  def delete(conn, %{"id" => name}) do
    case CachedPackages.delete_cached_package(name) do
      :ok ->
        conn
        |> put_flash(:info, "Package #{name} and all its releases deleted from cache")
        |> redirect(to: ~p"/cached-packages")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Package not found or not a cached package")
        |> redirect(to: ~p"/cached-packages")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to delete package")
        |> redirect(to: ~p"/cached-packages")
    end
  end

  @doc """
  Clears all cached packages.
  """
  def clear_all(conn, %{"confirm" => "true"}) do
    case CachedPackages.clear_all_cached_packages() do
      {:ok, count} ->
        conn
        |> put_flash(:info, "Successfully deleted #{count} cached packages")
        |> redirect(to: ~p"/cached-packages")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to clear cache")
        |> redirect(to: ~p"/cached-packages")
    end
  end

  def clear_all(conn, _params) do
    conn
    |> put_flash(:error, "Confirmation required to clear all cached packages")
    |> redirect(to: ~p"/cached-packages")
  end

  @doc """
  Refreshes all cached packages from upstream.
  Re-fetches metadata and downloads any new release tarballs.
  """
  def refresh_all(conn, _params) do
    case CachedPackages.refresh_all_cached_packages() do
      {:ok, %{refreshed: refreshed, new_releases: new_releases, errors: errors}} ->
        message =
          "Refreshed #{refreshed} packages, #{new_releases} new releases cached" <>
            if(errors != [], do: ", #{length(errors)} errors", else: "")

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/cached-packages")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to refresh: #{reason}")
        |> redirect(to: ~p"/cached-packages")
    end
  end

  @doc """
  Refreshes a single cached package from upstream.
  """
  def refresh(conn, %{"id" => name}) do
    case CachedPackages.refresh_cached_package(name) do
      {:ok, %{new_releases: count}} ->
        message =
          if count > 0,
            do: "Package #{name} refreshed, #{count} new releases cached",
            else: "Package #{name} refreshed, already up to date"

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/cached-packages/#{name}")

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_flash(:error, "Failed to refresh #{name}: #{reason}")
        |> redirect(to: ~p"/cached-packages/#{name}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to refresh #{name}: #{inspect(reason)}")
        |> redirect(to: ~p"/cached-packages/#{name}")
    end
  end

  # Private helpers

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val) and val > 0, do: val
  defp parse_int(_, default), do: default

  defp parse_sort("name"), do: :name
  defp parse_sort("downloads"), do: :downloads
  defp parse_sort("updated_at"), do: :updated_at
  defp parse_sort(_), do: :updated_at

  defp parse_sort_dir("asc"), do: :asc
  defp parse_sort_dir("desc"), do: :desc
  defp parse_sort_dir(_), do: :desc
end
