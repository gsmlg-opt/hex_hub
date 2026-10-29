defmodule HexHub.DatabaseBackupTest do
  use ExUnit.Case, async: false

  alias HexHub.Backup.{Exporter, Importer}
  alias HexHub.{Database, Packages, Users}

  setup do
    Database.reset_tables()
    on_exit(fn -> Database.reset_tables() end)
    :ok
  end

  @tag :tmp_dir
  test "backup metadata can be restored using the selected backend", %{tmp_dir: tmp_dir} do
    assert {:ok, _} = Users.create_user("backup_owner", "owner@example.com", "password123")

    assert {:ok, _} =
             Packages.create_package("backup_package", "hexpm", %{"description" => "Backup"})

    assert :ok = Packages.add_package_owner("backup_package", "backup_owner", "full")

    assert {:ok, _} =
             Packages.create_release(
               "backup_package",
               "1.0.0",
               %{"app" => "backup_package"},
               %{},
               "tarball"
             )

    path = Path.join(tmp_dir, "backup.tar")
    assert {:ok, %{user_count: 1, package_count: 1, release_count: 1}} = Exporter.export(path)

    Database.reset_tables()

    assert {:ok, %{users_restored: 1, packages_restored: 1, releases_restored: 1}} =
             Importer.import(path)

    assert {:ok, %{username: "backup_owner"}} = Users.authenticate("backup_owner", "password123")

    assert {:ok, %{name: "backup_package", source: :local}} =
             Packages.get_package("backup_package")

    assert {:ok, %{version: "1.0.0"}} = Packages.get_release("backup_package", "1.0.0")
    assert {:ok, [%{username: "backup_owner"}]} = Packages.get_package_owners("backup_package")
  end
end
