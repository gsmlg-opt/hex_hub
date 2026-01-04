defmodule HexHub.Backup.CleanupTest do
  use ExUnit.Case

  alias HexHub.Backup
  alias HexHub.Backup.Cleanup

  setup do
    # Clean test database
    HexHub.Users.reset_test_store()

    on_exit(fn ->
      # Clean up test files
      backup_path = Backup.backup_path()
      File.rm_rf(backup_path)
    end)

    :ok
  end

  describe "Cleanup GenServer" do
    test "process is running" do
      # Verify process is alive (it's started by the application)
      assert Process.alive?(Cleanup)
    end

    test "next_cleanup_at/0 returns scheduled time" do
      next_at = Cleanup.next_cleanup_at()

      assert next_at != nil
      assert is_struct(next_at, DateTime)
    end

    test "run_cleanup/0 triggers manual cleanup" do
      # Create test backup
      {:ok, backup} = Backup.create_backup_record("test_user")

      # Verify backup exists
      {:ok, [retrieved]} = Backup.list_backups()
      assert retrieved.id == backup.id

      # Trigger cleanup
      Cleanup.run_cleanup()

      # Give it a moment to process
      Process.sleep(100)

      # Since backup is not expired yet, it should still exist
      {:ok, backups} = Backup.list_backups()
      assert length(backups) == 1
    end
  end

  describe "cleanup_expired_backups/0" do
    test "deletes backups older than retention period" do
      # Create backup record
      {:ok, backup} = Backup.create_backup_record("test_user")

      # Manually set expires_at to past
      past_time = DateTime.add(DateTime.utc_now(), -60 * 60 * 24, :second)

      record = {
        :backups,
        backup.id,
        backup.filename,
        backup.file_path,
        backup.size_bytes,
        backup.user_count,
        backup.package_count,
        backup.release_count,
        backup.created_by,
        backup.status,
        backup.error_message,
        backup.created_at,
        backup.completed_at,
        past_time
      }

      :mnesia.transaction(fn ->
        :mnesia.write(record)
      end)

      # Create the file so cleanup can delete it
      File.mkdir_p!(Backup.backup_path())
      File.write!(backup.file_path, "test content")

      # Verify backup exists before cleanup
      {:ok, before} = Backup.list_backups()
      assert length(before) == 1

      # Run cleanup
      {:ok, deleted_count} = Backup.cleanup_expired_backups()

      # Should have deleted one backup
      assert deleted_count == 1

      # Verify backup is gone after cleanup
      {:ok, remaining} = Backup.list_backups()
      assert length(remaining) == 0
    end

    test "preserves backups within retention period" do
      # Create backup with future expiration
      {:ok, backup} = Backup.create_backup_record("test_user")

      # Verify backup exists
      {:ok, [retrieved]} = Backup.list_backups()
      assert retrieved.id == backup.id

      # Run cleanup
      {:ok, deleted_count} = Backup.cleanup_expired_backups()

      # Should not delete recent backup
      assert deleted_count == 0

      # Verify backup still exists
      {:ok, remaining} = Backup.list_backups()
      assert length(remaining) == 1
    end

    test "handles missing backup files gracefully" do
      # Create backup record without file
      {:ok, backup} = Backup.create_backup_record("test_user")

      # Set expiration to past
      past_time = DateTime.add(DateTime.utc_now(), -60 * 60 * 24, :second)

      record = {
        :backups,
        backup.id,
        backup.filename,
        backup.file_path,
        backup.size_bytes,
        backup.user_count,
        backup.package_count,
        backup.release_count,
        backup.created_by,
        backup.status,
        backup.error_message,
        backup.created_at,
        backup.completed_at,
        past_time
      }

      :mnesia.transaction(fn ->
        :mnesia.write(record)
      end)

      # Run cleanup (file doesn't exist, should handle gracefully)
      {:ok, deleted_count} = Backup.cleanup_expired_backups()

      # Should still mark as deleted even if file missing
      assert deleted_count == 1
    end

    test "handles multiple expired backups" do
      # Create multiple expired backups
      File.mkdir_p!(Backup.backup_path())

      for i <- 1..3 do
        {:ok, backup} = Backup.create_backup_record("test_user")
        File.write!(backup.file_path, "test content #{i}")

        # Set expiration to past
        past_time = DateTime.add(DateTime.utc_now(), -60 * 60 * 24 * i, :second)

        record = {
          :backups,
          backup.id,
          backup.filename,
          backup.file_path,
          backup.size_bytes,
          backup.user_count,
          backup.package_count,
          backup.release_count,
          backup.created_by,
          backup.status,
          backup.error_message,
          backup.created_at,
          backup.completed_at,
          past_time
        }

        :mnesia.transaction(fn ->
          :mnesia.write(record)
        end)
      end

      # Run cleanup
      {:ok, deleted_count} = Backup.cleanup_expired_backups()

      # Should delete all 3 expired backups
      assert deleted_count == 3

      # Verify all are gone
      {:ok, remaining} = Backup.list_backups()
      assert length(remaining) == 0
    end
  end
end
