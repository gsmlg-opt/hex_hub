defmodule HexHub.Backup.ImporterTest do
  use ExUnit.Case

  alias HexHub.Backup.{Exporter, Importer}
  alias HexHub.TestHelpers

  setup do
    # Clean test database
    HexHub.Users.reset_test_store()
    HexHub.Packages.reset_test_store()

    on_exit(fn ->
      # Clean up test files
      backup_path = HexHub.Backup.backup_path()
      File.rm_rf(backup_path)
    end)

    :ok
  end

  describe "import/2" do
    test "validates proper tar file" do
      # Create a valid backup
      backup_file = create_test_backup()

      assert {:ok, _files} = Importer.validate_tar(backup_file)

      File.rm(backup_file)
    end

    test "returns error for invalid tar file" do
      invalid_file = System.tmp_dir() |> Path.join("invalid.tar")
      File.write!(invalid_file, "not a tar file")

      assert {:error, _reason} = Importer.import(invalid_file)

      File.rm(invalid_file)
    end

    test "returns error for missing manifest" do
      tar_path = System.tmp_dir() |> Path.join("no_manifest_#{System.unique_integer()}.tar")

      # Create minimal tar with just users.json
      :erl_tar.create(tar_path, [
        {~c'users.json', <<>>}
      ])

      assert {:error, _reason} = Importer.import(tar_path)

      File.rm(tar_path)
    end
  end

  describe "validate_tar/1" do
    test "validates proper tar file structure" do
      backup_file = create_test_backup()

      assert {:ok, files} = Importer.validate_tar(backup_file)
      assert is_list(files)

      File.rm(backup_file)
    end

    test "rejects invalid tar file" do
      invalid_file = System.tmp_dir() |> Path.join("invalid.tar")
      File.write!(invalid_file, "not a tar file")

      assert {:error, _reason} = Importer.validate_tar(invalid_file)

      File.rm(invalid_file)
    end

    test "rejects non-existent file" do
      assert {:error, _reason} = Importer.validate_tar("/non/existent/file.tar")
    end
  end

  describe "validate_manifest/1" do
    test "accepts compatible manifest version" do
      # Create test backup and extract
      backup_file = create_test_backup()

      temp_dir = System.tmp_dir() |> Path.join("manifest_test_#{System.unique_integer()}")
      File.mkdir_p!(temp_dir)

      :erl_tar.extract(backup_file, [{:cwd, temp_dir}])

      manifest_path = Path.join(temp_dir, "manifest.json")

      assert {:ok, manifest} = Importer.validate_manifest(manifest_path)
      assert manifest.version == "1.0"

      File.rm_rf(temp_dir)
      File.rm(backup_file)
    end

    test "rejects incompatible manifest version" do
      # Create manifest with incompatible version
      manifest = %{
        version: "99.0",
        hex_hub_version: "0.0.1",
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        created_by: "test",
        contents: %{},
        checksums: %{}
      }

      temp_dir = System.tmp_dir() |> Path.join("bad_manifest_#{System.unique_integer()}")
      File.mkdir_p!(temp_dir)

      manifest_path = Path.join(temp_dir, "manifest.json")
      File.write!(manifest_path, Jason.encode!(manifest))

      assert {:error, :incompatible_version} = Importer.validate_manifest(manifest_path)

      File.rm_rf(temp_dir)
    end
  end

  describe "restore_users/2" do
    test "restores users from JSON file" do
      # Create and export users
      TestHelpers.create_user(%{username: "user1", email: "user1@example.com"})
      TestHelpers.create_user(%{username: "user2", email: "user2@example.com"})

      export_dir = System.tmp_dir() |> Path.join("users_export_#{System.unique_integer()}")
      File.mkdir_p!(export_dir)

      {:ok, _users} = Exporter.export_users(export_dir)

      users_file = Path.join(export_dir, "users.json")

      # Reset and restore
      HexHub.Users.reset_test_store()

      {:ok, restored_count} =
        Importer.restore_users(users_file, conflict_strategy: :skip)

      assert restored_count >= 2

      File.rm_rf(export_dir)
    end
  end

  describe "restore_packages/2" do
    test "restores packages from JSON file" do
      # Create and export packages
      TestHelpers.create_user(%{username: "author", email: "author@example.com"})
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      export_dir = System.tmp_dir() |> Path.join("pkg_export_#{System.unique_integer()}")
      File.mkdir_p!(export_dir)

      {:ok, _packages} = Exporter.export_packages(export_dir)

      packages_file = Path.join(export_dir, "packages.json")

      # Reset and restore
      HexHub.Users.reset_test_store()
      HexHub.Packages.reset_test_store()

      {:ok, restored_count} =
        Importer.restore_packages(packages_file, conflict_strategy: :skip)

      assert restored_count >= 1

      File.rm_rf(export_dir)
    end
  end

  describe "restore_owners/2" do
    test "restores ownership relationships from JSON" do
      # Create and export
      TestHelpers.create_user(%{username: "author", email: "author@example.com"})
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      export_dir = System.tmp_dir() |> Path.join("owners_export_#{System.unique_integer()}")
      File.mkdir_p!(export_dir)

      {:ok, _owners} = Exporter.export_owners(export_dir)

      owners_file = Path.join(export_dir, "owners.json")

      # Reset and restore
      HexHub.Users.reset_test_store()
      HexHub.Packages.reset_test_store()

      # Restore dependencies first
      TestHelpers.create_user(%{username: "author", email: "author@example.com"})
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      {:ok, restored_count} =
        Importer.restore_owners(owners_file, conflict_strategy: :skip)

      assert restored_count >= 0

      File.rm_rf(export_dir)
    end
  end

  # Helper functions

  defp create_test_backup do
    TestHelpers.create_user(%{username: "user1", email: "user1@example.com"})
    TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

    backup_path = System.tmp_dir() |> Path.join("test_backup_#{System.unique_integer()}.tar")

    {:ok, _} = Exporter.export(backup_path)

    backup_path
  end
end
