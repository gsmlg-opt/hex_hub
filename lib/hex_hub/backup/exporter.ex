defmodule HexHub.Backup.Exporter do
  @moduledoc """
  Handles streaming tar archive creation for backups.

  Uses Erlang's :erl_tar module for creating standard POSIX tar archives
  that are compatible with Unix tar utilities.
  """

  alias HexHub.Backup.Manifest

  @type export_result :: %{
          size_bytes: non_neg_integer(),
          user_count: non_neg_integer(),
          package_count: non_neg_integer(),
          release_count: non_neg_integer()
        }

  @doc """
  Exports all users and locally-published packages to a tar archive.

  Returns {:ok, result} with counts and size, or {:error, reason}.
  """
  @spec export(String.t()) :: {:ok, export_result()} | {:error, term()}
  def export(file_path) do
    # Create a temporary directory for building the archive contents
    tmp_dir = create_temp_dir()

    try do
      # Export all data to temp directory
      {:ok, users} = export_users(tmp_dir)
      {:ok, packages} = export_packages(tmp_dir)
      {:ok, releases} = export_releases(tmp_dir)
      {:ok, _owners} = export_owners(tmp_dir)

      # Copy package and doc tarballs
      {:ok, _package_files_count} = copy_package_tarballs(tmp_dir, packages)
      {:ok, _doc_files_count} = copy_doc_tarballs(tmp_dir, releases)

      # Generate manifest
      manifest =
        Manifest.generate("system", %{
          users: length(users),
          packages: length(packages),
          releases: length(releases),
          total_size_bytes: 0
        })

      manifest_path = Path.join(tmp_dir, "manifest.json")
      File.write!(manifest_path, Manifest.encode(manifest))

      # Create the tar archive
      create_tar_archive(file_path, tmp_dir)

      # Get the file size
      size_bytes =
        case File.stat(file_path) do
          {:ok, %{size: size}} -> size
          _ -> 0
        end

      emit_progress(:completed, 100)

      {:ok,
       %{
         size_bytes: size_bytes,
         user_count: length(users),
         package_count: length(packages),
         release_count: length(releases)
       }}
    rescue
      e ->
        {:error, Exception.message(e)}
    after
      # Clean up temp directory
      File.rm_rf(tmp_dir)
    end
  end

  @doc """
  Exports all users to a JSON file.

  Returns {:ok, users} where users is the list of exported user maps.
  """
  def export_users(tmp_dir) do
    emit_progress(:exporting_users, 10)

    users =
      case :mnesia.transaction(fn ->
             :mnesia.foldl(
               fn user, acc ->
                 [user_to_map(user) | acc]
               end,
               [],
               :users
             )
           end) do
        {:atomic, result} -> result
        {:aborted, _reason} -> []
      end

    users_path = Path.join(tmp_dir, "users.json")
    File.write!(users_path, Jason.encode!(users, pretty: true))

    {:ok, users}
  end

  @doc """
  Exports all locally-published packages to a JSON file.

  Returns {:ok, packages} where packages is the list of exported package maps.
  """
  def export_packages(tmp_dir) do
    emit_progress(:exporting_packages, 25)

    packages =
      case :mnesia.transaction(fn ->
             :mnesia.foldl(
               fn pkg, acc ->
                 # Only include locally published packages (source: :local)
                 source = elem(pkg, 10)

                 if source == :local do
                   [package_to_map(pkg) | acc]
                 else
                   acc
                 end
               end,
               [],
               :packages
             )
           end) do
        {:atomic, result} -> result
        {:aborted, _reason} -> []
      end

    # Create packages directory
    packages_dir = Path.join(tmp_dir, "packages")
    File.mkdir_p!(packages_dir)

    metadata_path = Path.join(packages_dir, "metadata.json")
    File.write!(metadata_path, Jason.encode!(packages, pretty: true))

    {:ok, packages}
  end

  @doc """
  Exports all releases for locally-published packages to a JSON file.

  Returns {:ok, releases} where releases is the list of exported release maps.
  """
  def export_releases(tmp_dir) do
    emit_progress(:exporting_releases, 40)

    # First get the list of local package names
    local_package_names =
      case :mnesia.transaction(fn ->
             :mnesia.foldl(
               fn pkg, acc ->
                 source = elem(pkg, 10)

                 if source == :local do
                   [elem(pkg, 1) | acc]
                 else
                   acc
                 end
               end,
               [],
               :packages
             )
           end) do
        {:atomic, names} -> MapSet.new(names)
        {:aborted, _} -> MapSet.new()
      end

    releases =
      case :mnesia.transaction(fn ->
             :mnesia.foldl(
               fn release, acc ->
                 package_name = elem(release, 1)

                 if MapSet.member?(local_package_names, package_name) do
                   [release_to_map(release) | acc]
                 else
                   acc
                 end
               end,
               [],
               :package_releases
             )
           end) do
        {:atomic, result} -> result
        {:aborted, _reason} -> []
      end

    releases_path = Path.join(tmp_dir, "releases.json")
    File.write!(releases_path, Jason.encode!(releases, pretty: true))

    {:ok, releases}
  end

  @doc """
  Exports package ownership records to a JSON file.

  Returns {:ok, owners} where owners is the list of exported ownership maps.
  """
  def export_owners(tmp_dir) do
    emit_progress(:exporting_owners, 50)

    # First get the list of local package names
    local_package_names =
      case :mnesia.transaction(fn ->
             :mnesia.foldl(
               fn pkg, acc ->
                 source = elem(pkg, 10)

                 if source == :local do
                   [elem(pkg, 1) | acc]
                 else
                   acc
                 end
               end,
               [],
               :packages
             )
           end) do
        {:atomic, names} -> MapSet.new(names)
        {:aborted, _} -> MapSet.new()
      end

    owners =
      case :mnesia.transaction(fn ->
             :mnesia.foldl(
               fn owner, acc ->
                 package_name = elem(owner, 1)

                 if MapSet.member?(local_package_names, package_name) do
                   [owner_to_map(owner) | acc]
                 else
                   acc
                 end
               end,
               [],
               :package_owners
             )
           end) do
        {:atomic, result} -> result
        {:aborted, _reason} -> []
      end

    owners_path = Path.join(tmp_dir, "owners.json")
    File.write!(owners_path, Jason.encode!(owners, pretty: true))

    {:ok, owners}
  end

  @doc """
  Copies package tarballs to the backup archive directory.

  Returns {:ok, count} with the number of files copied.
  """
  def copy_package_tarballs(tmp_dir, packages) do
    emit_progress(:copying_packages, 60)

    packages_dir = Path.join(tmp_dir, "packages")
    File.mkdir_p!(packages_dir)

    storage_path = Application.get_env(:hex_hub, :storage_path, "priv/storage")

    count =
      packages
      |> Enum.reduce(0, fn pkg, acc ->
        # For each package, find all versions and copy their tarballs
        package_name = Map.get(pkg, :name)

        # Get releases for this package
        releases = get_package_releases(package_name)

        Enum.reduce(releases, acc, fn release, inner_acc ->
          version = Map.get(release, :version)
          source_path = Path.join([storage_path, "tarballs", "#{package_name}-#{version}.tar"])

          if File.exists?(source_path) do
            dest_path = Path.join(packages_dir, "#{package_name}-#{version}.tar")
            File.cp!(source_path, dest_path)
            inner_acc + 1
          else
            inner_acc
          end
        end)
      end)

    {:ok, count}
  end

  @doc """
  Copies documentation tarballs to the backup archive directory.

  Returns {:ok, count} with the number of files copied.
  """
  def copy_doc_tarballs(tmp_dir, releases) do
    emit_progress(:copying_docs, 80)

    docs_dir = Path.join(tmp_dir, "docs")
    File.mkdir_p!(docs_dir)

    storage_path = Application.get_env(:hex_hub, :storage_path, "priv/storage")

    count =
      releases
      |> Enum.filter(fn release -> Map.get(release, :has_docs, false) end)
      |> Enum.reduce(0, fn release, acc ->
        package_name = Map.get(release, :package_name)
        version = Map.get(release, :version)
        source_path = Path.join([storage_path, "docs", "#{package_name}-#{version}.tar.gz"])

        if File.exists?(source_path) do
          dest_path = Path.join(docs_dir, "#{package_name}-#{version}.tar.gz")
          File.cp!(source_path, dest_path)
          acc + 1
        else
          acc
        end
      end)

    {:ok, count}
  end

  # Private functions

  defp create_temp_dir do
    tmp_base = System.tmp_dir!()
    tmp_dir = Path.join(tmp_base, "hexhub_backup_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp create_tar_archive(tar_path, source_dir) do
    emit_progress(:creating_archive, 90)

    # Get all files to add
    files =
      Path.wildcard(Path.join(source_dir, "**/*"))
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(fn full_path ->
        relative_path = Path.relative_to(full_path, source_dir)
        {String.to_charlist(relative_path), String.to_charlist(full_path)}
      end)

    # Create the tar archive
    tar_path_charlist = String.to_charlist(tar_path)

    case :erl_tar.create(tar_path_charlist, files) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to create tar archive: #{inspect(reason)}"
    end
  end

  defp get_package_releases(package_name) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object(
             {:package_releases, package_name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
           )
         end) do
      {:atomic, records} ->
        Enum.map(records, &release_to_map/1)

      {:aborted, _} ->
        []
    end
  end

  defp user_to_map(
         {:users, username, email, password_hash, _totp_secret, totp_enabled, _recovery_codes,
          service_account, deactivated_at, inserted_at, updated_at}
       ) do
    %{
      username: username,
      email: email,
      password_hash: password_hash,
      # totp_secret excluded for security
      totp_enabled: totp_enabled,
      # recovery_codes excluded for security
      service_account: service_account,
      deactivated_at: deactivated_at,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end

  defp package_to_map(
         {:packages, name, repository_name, meta, private, downloads, inserted_at, updated_at,
          html_url, docs_html_url, source}
       ) do
    %{
      name: name,
      repository_name: repository_name,
      meta: meta,
      private: private,
      downloads: downloads,
      inserted_at: inserted_at,
      updated_at: updated_at,
      html_url: html_url,
      docs_html_url: docs_html_url,
      source: source
    }
  end

  defp release_to_map(
         {:package_releases, package_name, version, has_docs, meta, requirements, retired,
          downloads, inserted_at, updated_at, url, package_url, html_url, docs_html_url}
       ) do
    %{
      package_name: package_name,
      version: version,
      has_docs: has_docs,
      meta: meta,
      requirements: requirements,
      retired: retired,
      downloads: downloads,
      inserted_at: inserted_at,
      updated_at: updated_at,
      url: url,
      package_url: package_url,
      html_url: html_url,
      docs_html_url: docs_html_url
    }
  end

  defp owner_to_map({:package_owners, package_name, username, level, inserted_at}) do
    %{
      package_name: package_name,
      username: username,
      level: level,
      inserted_at: inserted_at
    }
  end

  defp emit_progress(step, percent) do
    :telemetry.execute(
      [:hex_hub, :backup, :progress],
      %{percent: percent},
      %{step: step}
    )
  end
end
