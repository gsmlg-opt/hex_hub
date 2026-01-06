defmodule HexHub.Backup.Importer do
  @moduledoc """
  Handles tar archive extraction and system restoration from backups.

  Uses Erlang's :erl_tar module for extracting standard POSIX tar archives.
  """

  alias HexHub.Backup.Manifest

  @type import_result :: %{
          users_restored: non_neg_integer(),
          packages_restored: non_neg_integer(),
          releases_restored: non_neg_integer(),
          conflicts: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @type conflict_strategy :: :skip | :overwrite | :fail

  @doc """
  Imports users and packages from a backup tar archive.

  Options:
    - :conflict_strategy - :skip (default), :overwrite, or :fail

  Returns {:ok, result} with counts, or {:error, reason}.
  """
  @spec import(String.t(), keyword()) :: {:ok, import_result()} | {:error, term()}
  def import(file_path, opts \\ []) do
    strategy = Keyword.get(opts, :conflict_strategy, :skip)
    start_time = System.monotonic_time(:millisecond)

    with {:ok, _} <- validate_tar(file_path),
         {:ok, tmp_dir} <- extract_tar(file_path),
         {:ok, manifest} <- read_manifest(tmp_dir),
         :ok <- Manifest.validate(manifest) do
      try do
        # Restore in order: users first, then packages, releases, owners
        {:ok, users_result} = restore_users(tmp_dir, strategy)
        {:ok, packages_result} = restore_packages(tmp_dir, strategy)
        {:ok, releases_result} = restore_releases(tmp_dir, strategy)
        {:ok, owners_result} = restore_owners(tmp_dir, strategy)

        # Restore files
        {:ok, _} = restore_package_files(tmp_dir)
        {:ok, _} = restore_doc_files(tmp_dir)

        end_time = System.monotonic_time(:millisecond)

        {:ok,
         %{
           users_restored: users_result.restored,
           packages_restored: packages_result.restored,
           releases_restored: releases_result.restored,
           conflicts:
             users_result.conflicts + packages_result.conflicts + releases_result.conflicts +
               owners_result.conflicts,
           duration_ms: end_time - start_time
         }}
      after
        # Clean up temp directory
        File.rm_rf(tmp_dir)
      end
    end
  end

  @doc """
  Validates that a file is a valid tar archive.

  Returns {:ok, :valid} or {:error, reason}.
  """
  def validate_tar(file_path) do
    if File.exists?(file_path) do
      case :erl_tar.table(String.to_charlist(file_path)) do
        {:ok, _files} -> {:ok, :valid}
        {:error, reason} -> {:error, {:invalid_tar, reason}}
      end
    else
      {:error, :file_not_found}
    end
  end

  @doc """
  Validates the manifest for version compatibility.
  """
  def validate_manifest(manifest) do
    Manifest.validate(manifest)
  end

  @doc """
  Restores users from backup.

  Returns {:ok, %{restored: count, conflicts: count}} or {:error, reason}.
  """
  def restore_users(tmp_dir, strategy) do
    users_path = Path.join(tmp_dir, "users.json")

    if File.exists?(users_path) do
      users = users_path |> File.read!() |> Jason.decode!()
      do_restore_users(users, strategy)
    else
      {:ok, %{restored: 0, conflicts: 0}}
    end
  end

  @doc """
  Restores packages from backup.
  """
  def restore_packages(tmp_dir, strategy) do
    packages_path = Path.join([tmp_dir, "packages", "metadata.json"])

    if File.exists?(packages_path) do
      packages = packages_path |> File.read!() |> Jason.decode!()
      do_restore_packages(packages, strategy)
    else
      {:ok, %{restored: 0, conflicts: 0}}
    end
  end

  @doc """
  Restores releases from backup.
  """
  def restore_releases(tmp_dir, strategy) do
    releases_path = Path.join(tmp_dir, "releases.json")

    if File.exists?(releases_path) do
      releases = releases_path |> File.read!() |> Jason.decode!()
      do_restore_releases(releases, strategy)
    else
      {:ok, %{restored: 0, conflicts: 0}}
    end
  end

  @doc """
  Restores package ownership records.
  """
  def restore_owners(tmp_dir, strategy) do
    owners_path = Path.join(tmp_dir, "owners.json")

    if File.exists?(owners_path) do
      owners = owners_path |> File.read!() |> Jason.decode!()
      do_restore_owners(owners, strategy)
    else
      {:ok, %{restored: 0, conflicts: 0}}
    end
  end

  @doc """
  Copies package tarballs from backup to storage.
  """
  def restore_package_files(tmp_dir) do
    packages_dir = Path.join(tmp_dir, "packages")
    storage_path = Application.get_env(:hex_hub, :storage_path, "priv/storage")
    tarballs_dir = Path.join(storage_path, "tarballs")

    File.mkdir_p!(tarballs_dir)

    if File.exists?(packages_dir) do
      count =
        Path.wildcard(Path.join(packages_dir, "*.tar"))
        |> Enum.reduce(0, fn src_path, acc ->
          filename = Path.basename(src_path)
          dest_path = Path.join(tarballs_dir, filename)
          File.cp!(src_path, dest_path)
          acc + 1
        end)

      {:ok, count}
    else
      {:ok, 0}
    end
  end

  @doc """
  Copies documentation tarballs from backup to storage.
  """
  def restore_doc_files(tmp_dir) do
    docs_dir = Path.join(tmp_dir, "docs")
    storage_path = Application.get_env(:hex_hub, :storage_path, "priv/storage")
    storage_docs_dir = Path.join(storage_path, "docs")

    File.mkdir_p!(storage_docs_dir)

    if File.exists?(docs_dir) do
      count =
        Path.wildcard(Path.join(docs_dir, "*.tar.gz"))
        |> Enum.reduce(0, fn src_path, acc ->
          filename = Path.basename(src_path)
          dest_path = Path.join(storage_docs_dir, filename)
          File.cp!(src_path, dest_path)
          acc + 1
        end)

      {:ok, count}
    else
      {:ok, 0}
    end
  end

  # Private functions

  defp extract_tar(file_path) do
    tmp_base = System.tmp_dir!()
    tmp_dir = Path.join(tmp_base, "hexhub_restore_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    case :erl_tar.extract(String.to_charlist(file_path), [
           {:cwd, String.to_charlist(tmp_dir)},
           :compressed
         ]) do
      :ok ->
        {:ok, tmp_dir}

      {:error, :eof} ->
        # Try without compression
        case :erl_tar.extract(String.to_charlist(file_path), [
               {:cwd, String.to_charlist(tmp_dir)}
             ]) do
          :ok -> {:ok, tmp_dir}
          {:error, reason} -> {:error, {:extract_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:extract_failed, reason}}
    end
  end

  defp read_manifest(tmp_dir) do
    manifest_path = Path.join(tmp_dir, "manifest.json")

    if File.exists?(manifest_path) do
      manifest_path |> File.read!() |> Manifest.parse()
    else
      {:error, :missing_manifest}
    end
  end

  defp do_restore_users(users, strategy) do
    {restored, conflicts} =
      Enum.reduce(users, {0, 0}, fn user_data, {r, c} ->
        username = Map.get(user_data, "username")

        case check_user_exists(username) do
          true ->
            case strategy do
              :skip -> {r, c + 1}
              :overwrite -> {write_user(user_data) + r, c}
              :fail -> raise "User conflict: #{username}"
            end

          false ->
            {write_user(user_data) + r, c}
        end
      end)

    {:ok, %{restored: restored, conflicts: conflicts}}
  end

  defp do_restore_packages(packages, strategy) do
    {restored, conflicts} =
      Enum.reduce(packages, {0, 0}, fn pkg_data, {r, c} ->
        name = Map.get(pkg_data, "name")

        case check_package_exists(name) do
          true ->
            case strategy do
              :skip -> {r, c + 1}
              :overwrite -> {write_package(pkg_data) + r, c}
              :fail -> raise "Package conflict: #{name}"
            end

          false ->
            {write_package(pkg_data) + r, c}
        end
      end)

    {:ok, %{restored: restored, conflicts: conflicts}}
  end

  defp do_restore_releases(releases, strategy) do
    {restored, conflicts} =
      Enum.reduce(releases, {0, 0}, fn rel_data, {r, c} ->
        package_name = Map.get(rel_data, "package_name")
        version = Map.get(rel_data, "version")

        case check_release_exists(package_name, version) do
          true ->
            case strategy do
              :skip -> {r, c + 1}
              :overwrite -> {write_release(rel_data) + r, c}
              :fail -> raise "Release conflict: #{package_name}@#{version}"
            end

          false ->
            {write_release(rel_data) + r, c}
        end
      end)

    {:ok, %{restored: restored, conflicts: conflicts}}
  end

  defp do_restore_owners(owners, strategy) do
    {restored, conflicts} =
      Enum.reduce(owners, {0, 0}, fn owner_data, {r, c} ->
        package_name = Map.get(owner_data, "package_name")
        username = Map.get(owner_data, "username")

        case check_owner_exists(package_name, username) do
          true ->
            case strategy do
              :skip -> {r, c + 1}
              :overwrite -> {write_owner(owner_data) + r, c}
              :fail -> raise "Owner conflict: #{username} -> #{package_name}"
            end

          false ->
            {write_owner(owner_data) + r, c}
        end
      end)

    {:ok, %{restored: restored, conflicts: conflicts}}
  end

  defp check_user_exists(username) do
    case :mnesia.transaction(fn -> :mnesia.read(:users, username) end) do
      {:atomic, [_]} -> true
      _ -> false
    end
  end

  defp check_package_exists(name) do
    case :mnesia.transaction(fn -> :mnesia.read(:packages, name) end) do
      {:atomic, [_]} -> true
      _ -> false
    end
  end

  defp check_release_exists(package_name, version) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object(
             {:package_releases, package_name, version, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_,
              :_}
           )
         end) do
      {:atomic, [_ | _]} -> true
      _ -> false
    end
  end

  defp check_owner_exists(package_name, username) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object({:package_owners, package_name, username, :_, :_})
         end) do
      {:atomic, [_ | _]} -> true
      _ -> false
    end
  end

  defp write_user(data) do
    now = DateTime.utc_now()

    record =
      {:users, Map.get(data, "username"), Map.get(data, "email"), Map.get(data, "password_hash"),
       nil, Map.get(data, "totp_enabled", false), nil, Map.get(data, "service_account", false),
       parse_datetime(Map.get(data, "deactivated_at")),
       parse_datetime(Map.get(data, "inserted_at")) || now,
       parse_datetime(Map.get(data, "updated_at")) || now}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> 1
      _ -> 0
    end
  end

  defp write_package(data) do
    now = DateTime.utc_now()

    record =
      {:packages, Map.get(data, "name"), Map.get(data, "repository_name"),
       Map.get(data, "meta", %{}), Map.get(data, "private", false), Map.get(data, "downloads", 0),
       parse_datetime(Map.get(data, "inserted_at")) || now,
       parse_datetime(Map.get(data, "updated_at")) || now, Map.get(data, "html_url"),
       Map.get(data, "docs_html_url"), :local}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> 1
      _ -> 0
    end
  end

  defp write_release(data) do
    now = DateTime.utc_now()

    record =
      {:package_releases, Map.get(data, "package_name"), Map.get(data, "version"),
       Map.get(data, "has_docs", false), Map.get(data, "meta", %{}),
       Map.get(data, "requirements", %{}), Map.get(data, "retired"),
       Map.get(data, "downloads", 0), parse_datetime(Map.get(data, "inserted_at")) || now,
       parse_datetime(Map.get(data, "updated_at")) || now, Map.get(data, "url"),
       Map.get(data, "package_url"), Map.get(data, "html_url"), Map.get(data, "docs_html_url")}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> 1
      _ -> 0
    end
  end

  defp write_owner(data) do
    now = DateTime.utc_now()

    record =
      {:package_owners, Map.get(data, "package_name"), Map.get(data, "username"),
       Map.get(data, "level", "maintainer"), parse_datetime(Map.get(data, "inserted_at")) || now}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> 1
      _ -> 0
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: nil
end
