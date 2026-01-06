defmodule HexHubAdminWeb.BackupController do
  use HexHubAdminWeb, :controller

  alias HexHub.Backup

  @doc """
  Lists all backups (backup history).
  """
  def index(conn, _params) do
    case Backup.list_backups() do
      {:ok, backups} ->
        render(conn, :index, backups: backups)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to load backup history")
        |> render(:index, backups: [])
    end
  end

  @doc """
  Shows the create backup form.
  """
  def new(conn, _params) do
    # Get current system stats for display
    stats = get_system_stats()
    render(conn, :new, stats: stats)
  end

  @doc """
  Creates a new backup.
  """
  def create(conn, _params) do
    # Use "admin" as default creator - session-based user tracking not yet implemented
    created_by = "admin"

    case Backup.create_backup(created_by) do
      {:ok, backup} ->
        conn
        |> put_flash(:info, "Backup created successfully")
        |> redirect(to: ~p"/backups/#{backup.id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create backup: #{inspect(reason)}")
        |> redirect(to: ~p"/backups/new")
    end
  end

  @doc """
  Shows backup details.
  """
  def show(conn, %{"id" => id}) do
    case Backup.get_backup(id) do
      {:ok, backup} ->
        can_download = File.exists?(backup.file_path)
        render(conn, :show, backup: backup, can_download: can_download)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Backup not found")
        |> redirect(to: ~p"/backups")
    end
  end

  @doc """
  Downloads a backup file.
  """
  def download(conn, %{"id" => id}) do
    case Backup.get_backup(id) do
      {:ok, backup} ->
        if File.exists?(backup.file_path) do
          conn
          |> put_resp_content_type("application/x-tar")
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=\"#{backup.filename}\""
          )
          |> send_file(200, backup.file_path)
        else
          conn
          |> put_flash(:error, "Backup file not found on disk")
          |> redirect(to: ~p"/backups/#{id}")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Backup not found")
        |> redirect(to: ~p"/backups")
    end
  end

  @doc """
  Deletes a backup.
  """
  def delete(conn, %{"id" => id}) do
    case Backup.delete_backup(id) do
      :ok ->
        conn
        |> put_flash(:info, "Backup deleted successfully")
        |> redirect(to: ~p"/backups")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Backup not found")
        |> redirect(to: ~p"/backups")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to delete backup: #{inspect(reason)}")
        |> redirect(to: ~p"/backups")
    end
  end

  @doc """
  Shows the restore form.
  """
  def restore_form(conn, _params) do
    conflict_strategies = [
      {"Skip existing", "skip"},
      {"Overwrite existing", "overwrite"}
    ]

    render(conn, :restore, conflict_strategies: conflict_strategies)
  end

  @doc """
  Handles backup restore from uploaded file.
  """
  def restore(conn, %{"backup" => backup_params}) do
    upload = Map.get(backup_params, "file")
    strategy = Map.get(backup_params, "conflict_strategy", "skip") |> String.to_existing_atom()

    if upload do
      case Backup.restore_from_file(upload.path, conflict_strategy: strategy) do
        {:ok, result} ->
          conn
          |> put_flash(
            :info,
            "Restore completed: #{result.users_restored} users, #{result.packages_restored} packages"
          )
          |> redirect(to: ~p"/backups")

        {:error, reason} ->
          conn
          |> put_flash(:error, "Restore failed: #{inspect(reason)}")
          |> redirect(to: ~p"/backups/restore")
      end
    else
      conn
      |> put_flash(:error, "Please select a backup file to upload")
      |> redirect(to: ~p"/backups/restore")
    end
  end

  # Private functions

  defp get_system_stats do
    user_count = count_table(:users)
    package_count = count_local_packages()
    release_count = count_table(:package_releases)

    %{
      user_count: user_count,
      package_count: package_count,
      release_count: release_count
    }
  end

  defp count_table(table) do
    case :mnesia.table_info(table, :size) do
      count when is_integer(count) -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp count_local_packages do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn pkg, acc ->
               # source is at index 10 in the packages tuple
               source = elem(pkg, 10)
               if source == :local, do: acc + 1, else: acc
             end,
             0,
             :packages
           )
         end) do
      {:atomic, count} -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end
end
