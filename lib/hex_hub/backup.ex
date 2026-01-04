defmodule HexHub.Backup do
  @moduledoc """
  Context module for backup and restore operations.

  This module provides the main API for creating and restoring backups
  of users and locally-published packages.
  """

  alias HexHub.Backup.{Exporter, Importer}
  alias HexHub.Audit

  @type backup :: %{
          id: String.t(),
          filename: String.t(),
          file_path: String.t(),
          size_bytes: non_neg_integer(),
          user_count: non_neg_integer(),
          package_count: non_neg_integer(),
          release_count: non_neg_integer(),
          created_by: String.t(),
          status: :pending | :completed | :failed,
          error_message: String.t() | nil,
          created_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          expires_at: DateTime.t()
        }

  @type conflict_strategy :: :skip | :overwrite | :fail

  @doc """
  Returns the configured backup storage path.
  """
  def backup_path do
    Application.get_env(:hex_hub, :backup_path, "priv/backups")
  end

  @doc """
  Returns the configured retention period in days.
  """
  def retention_days do
    Application.get_env(:hex_hub, :backup_retention_days, 30)
  end

  @doc """
  Creates a new backup record with pending status.
  """
  def create_backup_record(created_by) do
    id = generate_id()
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, retention_days() * 24 * 60 * 60, :second)
    filename = "hexhub-backup-#{id}.tar"
    file_path = Path.join(backup_path(), filename)

    backup = %{
      id: id,
      filename: filename,
      file_path: file_path,
      size_bytes: 0,
      user_count: 0,
      package_count: 0,
      release_count: 0,
      created_by: created_by,
      status: :pending,
      error_message: nil,
      created_at: now,
      completed_at: nil,
      expires_at: expires_at
    }

    case write_backup(backup) do
      :ok -> {:ok, backup}
      error -> error
    end
  end

  @doc """
  Creates a full system backup.

  Returns {:ok, backup} on success or {:error, reason} on failure.
  """
  def create_backup(created_by) do
    with {:ok, backup} <- create_backup_record(created_by),
         :ok <- ensure_backup_dir(),
         {:ok, result} <- Exporter.export(backup.file_path) do
      # Update backup record with results
      updated_backup = %{
        backup
        | status: :completed,
          size_bytes: result.size_bytes,
          user_count: result.user_count,
          package_count: result.package_count,
          release_count: result.release_count,
          completed_at: DateTime.utc_now()
      }

      case write_backup(updated_backup) do
        :ok ->
          emit_backup_created(updated_backup)
          log_backup_audit(:created, updated_backup)
          {:ok, updated_backup}

        error ->
          error
      end
    else
      {:error, reason} = error ->
        # Try to mark backup as failed if we have an id
        HexHub.Telemetry.log(:error, :backup, "Backup creation failed", %{reason: inspect(reason)})
        error
    end
  end

  @doc """
  Lists all backup records, sorted by creation date (newest first).
  """
  def list_backups do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn record, acc ->
               [record_to_map(record) | acc]
             end,
             [],
             :backups
           )
         end) do
      {:atomic, backups} ->
        sorted =
          backups
          |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

        {:ok, sorted}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a single backup by ID.
  """
  def get_backup(id) do
    case :mnesia.transaction(fn ->
           :mnesia.read(:backups, id)
         end) do
      {:atomic, [record]} ->
        {:ok, record_to_map(record)}

      {:atomic, []} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a backup record and its associated file.
  """
  def delete_backup(id) do
    case get_backup(id) do
      {:ok, backup} ->
        # Delete the file if it exists
        if File.exists?(backup.file_path) do
          File.rm(backup.file_path)
        end

        # Delete the record
        case :mnesia.transaction(fn ->
               :mnesia.delete({:backups, id})
             end) do
          {:atomic, :ok} ->
            emit_backup_deleted(backup, :manual)
            log_backup_audit(:deleted, backup)
            :ok

          {:aborted, reason} ->
            {:error, reason}
        end

      error ->
        error
    end
  end

  @doc """
  Restores from a backup file.

  Options:
    - :conflict_strategy - :skip (default), :overwrite, or :fail
  """
  def restore_from_file(file_path, opts \\ []) do
    strategy = Keyword.get(opts, :conflict_strategy, :skip)

    emit_restore_started(file_path, strategy)

    case Importer.import(file_path, conflict_strategy: strategy) do
      {:ok, result} ->
        emit_restore_completed(result)
        log_restore_audit(file_path, result)
        {:ok, result}

      {:error, reason} = error ->
        HexHub.Telemetry.log(:error, :backup, "Restore failed", %{reason: inspect(reason)})
        error
    end
  end

  @doc """
  Deletes all backups that have expired.
  """
  def cleanup_expired_backups do
    now = DateTime.utc_now()

    case list_backups() do
      {:ok, backups} ->
        expired =
          Enum.filter(backups, fn backup ->
            DateTime.compare(backup.expires_at, now) == :lt
          end)

        Enum.each(expired, fn backup ->
          case delete_backup(backup.id) do
            :ok ->
              emit_backup_deleted(backup, :expired)

            {:error, reason} ->
              HexHub.Telemetry.log(:warning, :general, "Failed to delete expired backup", %{
                backup_id: backup.id,
                reason: inspect(reason)
              })
          end
        end)

        {:ok, length(expired)}

      error ->
        error
    end
  end

  @doc """
  Checks if there is enough disk space for a backup.
  Returns {:ok, available_bytes} or {:error, :insufficient_space}.
  """
  def check_disk_space do
    path = backup_path()
    File.mkdir_p!(path)

    case :disksup.get_disk_data() do
      data when is_list(data) ->
        # Find the disk that contains our backup path
        abs_path = Path.expand(path)

        disk_info =
          Enum.find(data, fn {mount_point, _total, _percent} ->
            String.starts_with?(abs_path, to_string(mount_point))
          end)

        case disk_info do
          {_mount, total_kb, used_percent} ->
            available_kb = trunc(total_kb * (100 - used_percent) / 100)
            # Require at least 100MB free
            if available_kb > 100_000 do
              {:ok, available_kb * 1024}
            else
              {:error, :insufficient_space}
            end

          nil ->
            # Disk info not found, assume OK
            {:ok, :unknown}
        end

      _ ->
        # disksup not available, assume OK
        {:ok, :unknown}
    end
  end

  # Private functions

  defp ensure_backup_dir do
    path = backup_path()

    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp write_backup(backup) do
    record =
      {:backups, backup.id, backup.filename, backup.file_path, backup.size_bytes,
       backup.user_count, backup.package_count, backup.release_count, backup.created_by,
       backup.status, backup.error_message, backup.created_at, backup.completed_at,
       backup.expires_at}

    case :mnesia.transaction(fn ->
           :mnesia.write(record)
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp record_to_map(
         {:backups, id, filename, file_path, size_bytes, user_count, package_count, release_count,
          created_by, status, error_message, created_at, completed_at, expires_at}
       ) do
    %{
      id: id,
      filename: filename,
      file_path: file_path,
      size_bytes: size_bytes,
      user_count: user_count,
      package_count: package_count,
      release_count: release_count,
      created_by: created_by,
      status: status,
      error_message: error_message,
      created_at: created_at,
      completed_at: completed_at,
      expires_at: expires_at
    }
  end

  # Telemetry events

  defp emit_backup_created(backup) do
    :telemetry.execute(
      [:hex_hub, :backup, :created],
      %{size_bytes: backup.size_bytes},
      %{
        backup_id: backup.id,
        user_count: backup.user_count,
        package_count: backup.package_count,
        release_count: backup.release_count,
        created_by: backup.created_by
      }
    )
  end

  defp emit_backup_deleted(backup, reason) do
    :telemetry.execute(
      [:hex_hub, :backup, :deleted],
      %{},
      %{backup_id: backup.id, reason: reason}
    )
  end

  defp emit_restore_started(file_path, strategy) do
    :telemetry.execute(
      [:hex_hub, :backup, :restore, :start],
      %{},
      %{file_path: file_path, strategy: strategy}
    )
  end

  defp emit_restore_completed(result) do
    :telemetry.execute(
      [:hex_hub, :backup, :restore, :complete],
      %{duration_ms: Map.get(result, :duration_ms, 0)},
      %{
        users_restored: Map.get(result, :users_restored, 0),
        packages_restored: Map.get(result, :packages_restored, 0),
        releases_restored: Map.get(result, :releases_restored, 0),
        conflicts: Map.get(result, :conflicts, 0)
      }
    )
  end

  # Audit logging functions

  defp log_backup_audit(:created, backup) do
    Audit.log_event(
      "backup.created",
      "backup",
      backup.id,
      %{
        filename: backup.filename,
        size_bytes: backup.size_bytes,
        user_count: backup.user_count,
        package_count: backup.package_count,
        release_count: backup.release_count,
        created_by: backup.created_by
      }
    )
  end

  defp log_backup_audit(:deleted, backup) do
    Audit.log_event(
      "backup.deleted",
      "backup",
      backup.id,
      %{
        filename: backup.filename,
        created_by: backup.created_by
      }
    )
  end

  defp log_restore_audit(file_path, result) do
    Audit.log_event(
      "backup.restored",
      "backup",
      Path.basename(file_path),
      %{
        users_restored: result.users_restored,
        packages_restored: result.packages_restored,
        releases_restored: result.releases_restored,
        conflicts: result.conflicts,
        duration_ms: result.duration_ms
      }
    )
  end
end
