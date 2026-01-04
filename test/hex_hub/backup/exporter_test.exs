defmodule HexHub.Backup.ExporterTest do
  use ExUnit.Case

  alias HexHub.Backup.Exporter
  alias HexHub.TestHelpers

  setup do
    # Clean test database
    HexHub.Users.reset_test_store()
    HexHub.Packages.reset_test_store()

    on_exit(fn ->
      # Clean up created test files
      backup_path = HexHub.Backup.backup_path()
      File.rm_rf(backup_path)
    end)

    :ok
  end

  describe "export/1" do
    test "creates a tar file with all system data" do
      # Setup test data - use test helpers
      TestHelpers.create_user(%{username: "user1", email: "user1@example.com"})
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      # Create export
      backup_path = System.tmp_dir() |> Path.join("test_backup_#{System.unique_integer()}.tar")

      assert {:ok, result} = Exporter.export(backup_path)

      # Verify file exists
      assert File.exists?(backup_path)

      # Verify result contains metadata
      assert result.size_bytes > 0
      assert result.user_count >= 1
      assert result.package_count >= 1

      # Cleanup
      File.rm(backup_path)
    end

    test "handles empty system (no users or packages)" do
      backup_path = System.tmp_dir() |> Path.join("test_backup_empty_#{System.unique_integer()}.tar")

      assert {:ok, result} = Exporter.export(backup_path)

      assert File.exists?(backup_path)
      assert result.user_count == 0
      assert result.package_count == 0

      File.rm(backup_path)
    end

    test "tar file contains expected files" do
      TestHelpers.create_user(%{username: "user1", email: "user1@example.com"})
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      backup_path = System.tmp_dir() |> Path.join("test_backup_structure_#{System.unique_integer()}.tar")

      {:ok, _result} = Exporter.export(backup_path)

      # Extract and verify contents
      assert {:ok, files} = :erl_tar.table(backup_path)

      file_list = Enum.map(files, fn
        {:file, name} -> name
        {name, _type, _access} -> name
      end)

      # Should contain manifest
      assert Enum.any?(file_list, &String.ends_with?(&1, "manifest.json"))

      # Should contain users.json
      assert Enum.any?(file_list, &String.contains?(&1, "users.json"))

      # Should contain packages.json
      assert Enum.any?(file_list, &String.contains?(&1, "packages.json"))

      File.rm(backup_path)
    end

    test "returns error if path is invalid" do
      invalid_path = "/invalid/directory/that/does/not/exist/backup.tar"

      assert {:error, _reason} = Exporter.export(invalid_path)
    end
  end

  describe "export_users/1" do
    test "returns all users as JSON" do
      TestHelpers.create_user(%{username: "user1", email: "user1@example.com"})
      TestHelpers.create_user(%{username: "user2", email: "user2@example.com"})

      {:ok, users} = Exporter.export_users(System.tmp_dir())

      assert length(users) >= 2

      # Verify file was created
      users_file = Path.join(System.tmp_dir(), "users.json")
      assert File.exists?(users_file)

      # Verify file contains valid JSON
      content = File.read!(users_file)
      assert String.length(content) > 0

      File.rm(users_file)
    end

    test "handles empty user list" do
      {:ok, users} = Exporter.export_users(System.tmp_dir())

      assert length(users) == 0

      # Verify file was created
      users_file = Path.join(System.tmp_dir(), "users.json")
      assert File.exists?(users_file)

      File.rm(users_file)
    end
  end

  describe "export_packages/1" do
    test "returns all packages as JSON" do
      TestHelpers.create_package(%{name: "test_pkg1", meta: %{description: "Test1"}})
      TestHelpers.create_package(%{name: "test_pkg2", meta: %{description: "Test2"}})

      {:ok, packages} = Exporter.export_packages(System.tmp_dir())

      assert length(packages) >= 2

      packages_file = Path.join(System.tmp_dir(), "packages.json")
      assert File.exists?(packages_file)

      File.rm(packages_file)
    end
  end

  describe "export_releases/1" do
    test "exports releases for all packages" do
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      {:ok, releases} = Exporter.export_releases(System.tmp_dir())

      # May be 0 or more releases
      assert is_list(releases)

      releases_file = Path.join(System.tmp_dir(), "releases.json")
      assert File.exists?(releases_file)

      File.rm(releases_file)
    end
  end

  describe "export_owners/1" do
    test "exports ownership relationships" do
      TestHelpers.create_user(%{username: "owner", email: "owner@example.com"})
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      {:ok, owners} = Exporter.export_owners(System.tmp_dir())

      assert is_list(owners)

      owners_file = Path.join(System.tmp_dir(), "owners.json")
      assert File.exists?(owners_file)

      File.rm(owners_file)
    end
  end

  describe "copy_package_tarballs/2" do
    test "copies package tarball files to backup directory" do
      TestHelpers.create_package(%{name: "test_pkg", meta: %{description: "Test"}})

      backup_dir = System.tmp_dir() |> Path.join("backup_#{System.unique_integer()}")
      File.mkdir_p!(backup_dir)

      {:ok, result} = Exporter.copy_package_tarballs(backup_dir, System.tmp_dir())

      assert result.count >= 0
      assert result.total_size >= 0

      File.rm_rf(backup_dir)
    end
  end

  describe "copy_doc_tarballs/2" do
    test "copies documentation files to backup directory" do
      backup_dir = System.tmp_dir() |> Path.join("backup_#{System.unique_integer()}")
      File.mkdir_p!(backup_dir)

      {:ok, result} = Exporter.copy_doc_tarballs(backup_dir, System.tmp_dir())

      assert result.count >= 0
      assert result.total_size >= 0

      File.rm_rf(backup_dir)
    end
  end
end
