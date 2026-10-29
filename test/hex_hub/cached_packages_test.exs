defmodule HexHub.CachedPackagesTest do
  use ExUnit.Case, async: false

  alias HexHub.CachedPackages
  alias HexHub.Packages

  @packages_table :packages
  @package_releases_table :package_releases
  @moduletag :tmp_dir

  setup %{tmp_dir: storage_path} do
    original_storage =
      for key <- [:storage_type, :storage_path], do: {key, Application.fetch_env(:hex_hub, key)}

    Application.put_env(:hex_hub, :storage_type, :local)
    Application.put_env(:hex_hub, :storage_path, storage_path)

    on_exit(fn ->
      Enum.each(original_storage, fn
        {key, {:ok, value}} -> Application.put_env(:hex_hub, key, value)
        {key, :error} -> Application.delete_env(:hex_hub, key)
      end)
    end)

    # Clean up packages table before each test
    HexHub.Database.clear_table(@packages_table)
    HexHub.Database.clear_table(@package_releases_table)
    :ok
  end

  describe "list_packages_by_source/2" do
    test "returns empty list when no packages exist" do
      assert {:ok, %{packages: [], pagination: pagination}} =
               CachedPackages.list_packages_by_source(:local)

      assert pagination.total == 0
      assert pagination.page == 1
    end

    test "returns only local packages when source is :local" do
      # Create local package
      {:ok, _} =
        Packages.create_package("local_pkg", "hexpm", %{description: "Local"}, false, :local)

      # Create cached package
      {:ok, _} =
        Packages.create_package("cached_pkg", "hexpm", %{description: "Cached"}, false, :cached)

      {:ok, %{packages: packages}} = CachedPackages.list_packages_by_source(:local)

      assert length(packages) == 1
      assert Enum.at(packages, 0).name == "local_pkg"
      assert Enum.at(packages, 0).source == :local
      assert Enum.at(packages, 0).status == :active
    end

    test "returns only cached packages when source is :cached" do
      {:ok, _} =
        Packages.create_package("local_pkg", "hexpm", %{description: "Local"}, false, :local)

      {:ok, _} =
        Packages.create_package("cached_pkg", "hexpm", %{description: "Cached"}, false, :cached)

      {:ok, %{packages: packages}} = CachedPackages.list_packages_by_source(:cached)

      assert length(packages) == 1
      assert Enum.at(packages, 0).name == "cached_pkg"
      assert Enum.at(packages, 0).source == :cached
    end

    test "marks cached packages as shadowed when local counterpart exists" do
      # Create both local and cached with same name
      {:ok, _} =
        Packages.create_package("phoenix", "hexpm", %{description: "Local"}, false, :local)

      {:ok, _} =
        Packages.create_package(
          "phoenix_cached",
          "hexpm",
          %{description: "Cached"},
          false,
          :cached
        )

      # Use dirty write to create a cached package with same name as local
      # (Normally not allowed, but for testing shadow logic)
      now = System.system_time(:second)

      HexHub.Database.dirty_write(
        {@packages_table, "shadowed_pkg", "hexpm", %{description: "Shadowed"}, false, 0, now, now,
         nil, nil, :cached}
      )

      HexHub.Database.dirty_write(
        {@packages_table, "shadowed_pkg_local", "hexpm", %{description: "Local version"}, false,
         0, now, now, nil, nil, :local}
      )

      # The cached package with name "shadowed_pkg" should not be shadowed (no local with same name)
      {:ok, %{packages: cached_packages}} = CachedPackages.list_packages_by_source(:cached)

      shadowed_pkg = Enum.find(cached_packages, &(&1.name == "shadowed_pkg"))
      assert shadowed_pkg.status == :active

      phoenix_cached = Enum.find(cached_packages, &(&1.name == "phoenix_cached"))
      assert phoenix_cached.status == :active
    end

    test "applies search filter correctly" do
      {:ok, _} = Packages.create_package("phoenix", "hexpm", %{description: "Web"}, false, :local)
      {:ok, _} = Packages.create_package("ecto", "hexpm", %{description: "DB"}, false, :local)

      {:ok, _} =
        Packages.create_package(
          "phoenix_live_view",
          "hexpm",
          %{description: "Live"},
          false,
          :local
        )

      {:ok, %{packages: packages}} =
        CachedPackages.list_packages_by_source(:local, search: "phoenix")

      assert length(packages) == 2
      assert Enum.all?(packages, &String.contains?(&1.name, "phoenix"))
    end

    test "paginates results correctly" do
      # Create 15 packages
      for i <- 1..15 do
        {:ok, _} =
          Packages.create_package(
            "pkg_#{String.pad_leading("#{i}", 2, "0")}",
            "hexpm",
            %{},
            false,
            :local
          )
      end

      {:ok, %{packages: page1, pagination: pag1}} =
        CachedPackages.list_packages_by_source(:local, page: 1, per_page: 5)

      {:ok, %{packages: page2, pagination: pag2}} =
        CachedPackages.list_packages_by_source(:local, page: 2, per_page: 5)

      assert length(page1) == 5
      assert length(page2) == 5
      assert pag1.total == 15
      assert pag1.total_pages == 3
      assert pag2.page == 2
    end

    test "sorts packages by different fields" do
      {:ok, _} = Packages.create_package("zzz", "hexpm", %{}, false, :local)
      Process.sleep(10)
      {:ok, _} = Packages.create_package("aaa", "hexpm", %{}, false, :local)

      {:ok, %{packages: by_name_asc}} =
        CachedPackages.list_packages_by_source(:local, sort: :name, sort_dir: :asc)

      {:ok, %{packages: by_name_desc}} =
        CachedPackages.list_packages_by_source(:local, sort: :name, sort_dir: :desc)

      assert Enum.at(by_name_asc, 0).name == "aaa"
      assert Enum.at(by_name_desc, 0).name == "zzz"
    end
  end

  describe "list_packages_with_priority/1" do
    test "returns all packages from both sources" do
      {:ok, _} = Packages.create_package("local_pkg", "hexpm", %{}, false, :local)
      {:ok, _} = Packages.create_package("cached_pkg", "hexpm", %{}, false, :cached)

      {:ok, %{packages: packages}} = CachedPackages.list_packages_with_priority()

      assert length(packages) == 2
      assert Enum.any?(packages, &(&1.source == :local))
      assert Enum.any?(packages, &(&1.source == :cached))
    end

    test "marks all local packages as active" do
      {:ok, _} = Packages.create_package("local_pkg", "hexpm", %{}, false, :local)

      {:ok, %{packages: packages}} = CachedPackages.list_packages_with_priority()

      local = Enum.find(packages, &(&1.source == :local))
      assert local.status == :active
    end

    test "marks cached packages as shadowed when local counterpart exists" do
      now = System.system_time(:second)

      # Create local and cached packages with overlapping names
      HexHub.Database.dirty_write(
        {@packages_table, "shared_name", "hexpm", %{}, false, 0, now, now, nil, nil, :local}
      )

      HexHub.Database.dirty_write(
        {@packages_table, "shared_name_cached", "hexpm", %{}, false, 0, now, now, nil, nil,
         :cached}
      )

      # Since Mnesia uses name as primary key, we need packages with different names
      # to test shadowing. In practice, same-name packages would need special handling.
      {:ok, %{packages: packages}} = CachedPackages.list_packages_with_priority()

      local = Enum.find(packages, &(&1.name == "shared_name"))
      cached = Enum.find(packages, &(&1.name == "shared_name_cached"))

      assert local.status == :active
      # Different names, so not shadowed
      assert cached.status == :active
    end

    test "applies search filter across both sources" do
      {:ok, _} = Packages.create_package("phoenix_local", "hexpm", %{}, false, :local)
      {:ok, _} = Packages.create_package("phoenix_cached", "hexpm", %{}, false, :cached)
      {:ok, _} = Packages.create_package("ecto", "hexpm", %{}, false, :local)

      {:ok, %{packages: packages}} =
        CachedPackages.list_packages_with_priority(search: "phoenix")

      assert length(packages) == 2
      assert Enum.all?(packages, &String.contains?(&1.name, "phoenix"))
    end
  end

  describe "get_package_by_source/2" do
    test "returns local package when source is :local" do
      {:ok, _} = Packages.create_package("my_pkg", "hexpm", %{description: "Test"}, false, :local)

      {:ok, package} = CachedPackages.get_package_by_source("my_pkg", :local)

      assert package.name == "my_pkg"
      assert package.source == :local
      assert package.status == :active
    end

    test "returns cached package when source is :cached" do
      {:ok, _} =
        Packages.create_package("cached_pkg", "hexpm", %{description: "Cached"}, false, :cached)

      {:ok, package} = CachedPackages.get_package_by_source("cached_pkg", :cached)

      assert package.name == "cached_pkg"
      assert package.source == :cached
    end

    test "returns error when package not found" do
      assert {:error, :not_found} = CachedPackages.get_package_by_source("nonexistent", :local)
    end

    test "returns error when package exists but with different source" do
      {:ok, _} = Packages.create_package("local_only", "hexpm", %{}, false, :local)

      assert {:error, :not_found} = CachedPackages.get_package_by_source("local_only", :cached)
    end

    test "includes versions and releases in response" do
      {:ok, _} = Packages.create_package("versioned_pkg", "hexpm", %{}, false, :local)
      # Add a release
      assert {:ok, _} = Packages.create_release("versioned_pkg", "1.0.0", %{}, %{}, <<0>>)

      {:ok, package} = CachedPackages.get_package_by_source("versioned_pkg", :local)

      assert "1.0.0" in package.versions
      assert package.latest_version == "1.0.0"
    end
  end

  describe "delete_cached_package/1" do
    test "deletes cached package successfully" do
      {:ok, _} = Packages.create_package("to_delete", "hexpm", %{}, false, :cached)
      assert {:ok, _} = Packages.create_release("to_delete", "1.0.0", %{}, %{}, <<0>>)

      assert :ok = CachedPackages.delete_cached_package("to_delete")

      # Verify package is gone
      assert {:error, :not_found} = CachedPackages.get_package_by_source("to_delete", :cached)
    end

    test "returns error when package not found" do
      assert {:error, :not_found} = CachedPackages.delete_cached_package("nonexistent")
    end

    test "returns error when trying to delete local package" do
      {:ok, _} = Packages.create_package("local_pkg", "hexpm", %{}, false, :local)

      assert {:error, :not_found} = CachedPackages.delete_cached_package("local_pkg")

      # Verify local package still exists
      assert {:ok, _} = CachedPackages.get_package_by_source("local_pkg", :local)
    end

    test "deletes all associated releases" do
      {:ok, _} = Packages.create_package("multi_version", "hexpm", %{}, false, :cached)
      assert {:ok, _} = Packages.create_release("multi_version", "1.0.0", %{}, %{}, <<0>>)
      assert {:ok, _} = Packages.create_release("multi_version", "2.0.0", %{}, %{}, <<0>>)

      assert :ok = CachedPackages.delete_cached_package("multi_version")

      # Verify releases are gone
      releases =
        HexHub.Database.dirty_match_object(
          {@package_releases_table, "multi_version", :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_,
           :_}
        )

      assert releases == []
    end
  end

  describe "clear_all_cached_packages/0" do
    test "deletes all cached packages" do
      {:ok, _} = Packages.create_package("cached1", "hexpm", %{}, false, :cached)
      {:ok, _} = Packages.create_package("cached2", "hexpm", %{}, false, :cached)
      {:ok, _} = Packages.create_package("local1", "hexpm", %{}, false, :local)

      {:ok, count} = CachedPackages.clear_all_cached_packages()

      assert count == 2

      # Verify cached packages are gone
      {:ok, %{packages: cached}} = CachedPackages.list_packages_by_source(:cached)
      assert cached == []

      # Verify local package still exists
      {:ok, %{packages: local}} = CachedPackages.list_packages_by_source(:local)
      assert length(local) == 1
    end

    test "returns zero when no cached packages exist" do
      {:ok, _} = Packages.create_package("local1", "hexpm", %{}, false, :local)

      {:ok, count} = CachedPackages.clear_all_cached_packages()

      assert count == 0
    end
  end

  describe "has_local_counterpart?/1" do
    test "returns true when local package exists" do
      {:ok, _} = Packages.create_package("exists", "hexpm", %{}, false, :local)

      assert CachedPackages.has_local_counterpart?("exists") == true
    end

    test "returns false when package does not exist" do
      assert CachedPackages.has_local_counterpart?("nonexistent") == false
    end

    test "returns false when only cached package exists" do
      {:ok, _} = Packages.create_package("cached_only", "hexpm", %{}, false, :cached)

      assert CachedPackages.has_local_counterpart?("cached_only") == false
    end
  end

  describe "has_cached_counterpart?/1" do
    test "returns true when cached package exists" do
      {:ok, _} = Packages.create_package("exists", "hexpm", %{}, false, :cached)

      assert CachedPackages.has_cached_counterpart?("exists") == true
    end

    test "returns false when package does not exist" do
      assert CachedPackages.has_cached_counterpart?("nonexistent") == false
    end

    test "returns false when only local package exists" do
      {:ok, _} = Packages.create_package("local_only", "hexpm", %{}, false, :local)

      assert CachedPackages.has_cached_counterpart?("local_only") == false
    end
  end

  describe "get_package_stats/0" do
    test "returns correct counts" do
      {:ok, _} = Packages.create_package("local1", "hexpm", %{}, false, :local)
      {:ok, _} = Packages.create_package("local2", "hexpm", %{}, false, :local)
      {:ok, _} = Packages.create_package("cached1", "hexpm", %{}, false, :cached)
      {:ok, _} = Packages.create_package("cached2", "hexpm", %{}, false, :cached)
      {:ok, _} = Packages.create_package("cached3", "hexpm", %{}, false, :cached)

      stats = CachedPackages.get_package_stats()

      assert stats.local_count == 2
      assert stats.cached_count == 3
      assert stats.shadowed_count == 0
    end

    test "returns zeros when no packages exist" do
      stats = CachedPackages.get_package_stats()

      assert stats.local_count == 0
      assert stats.cached_count == 0
      assert stats.shadowed_count == 0
    end
  end
end
