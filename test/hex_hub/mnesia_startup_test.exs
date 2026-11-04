defmodule HexHub.MnesiaStartupTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "cold startup uses the requested directory and preserves disk records across VMs", %{
    tmp_dir: tmp_dir
  } do
    directory = Path.join(tmp_dir, "metadata")
    previous = Path.join(tmp_dir, "previous")

    run_in_vm!(directory, """
    Application.put_env(:mnesia, :dir, ~c#{inspect(previous)})
    :ok = HexHub.Mnesia.init()
    true = Path.expand(to_string(:mnesia.system_info(:directory))) == #{inspect(directory)}
    :disc_copies = :mnesia.table_info(:system_metadata, :storage_type)
    :ram_copies = :mnesia.table_info(:rate_limit, :storage_type)
    :ok = :mnesia.dirty_write({:system_metadata, "startup", <<0, 255, 128>>})
    :ok = :mnesia.sync_log()
    :stopped = :mnesia.stop()
    """)

    run_in_vm!(directory, """
    :ok = HexHub.Mnesia.init()
    [{:system_metadata, "startup", <<0, 255, 128>>}] =
      :mnesia.dirty_read(:system_metadata, "startup")
    :disc_copies = :mnesia.table_info(:system_metadata, :storage_type)
    :stopped = :mnesia.stop()
    """)

    refute File.exists?(previous)
    assert [] = Path.wildcard(Path.join(directory, ".hex_hub_write_check_*"), match_dot: true)
  end

  test "an unwritable directory produces an actionable error before starting Mnesia", %{
    tmp_dir: tmp_dir
  } do
    directory = Path.join(tmp_dir, "metadata")
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o500)
    on_exit(fn -> File.chmod!(directory, 0o700) end)

    output =
      run_in_vm!(directory, """
      try do
        HexHub.Mnesia.init()
      rescue
        error in RuntimeError -> IO.puts("STARTUP_ERROR: " <> Exception.message(error))
      end
      :no = :mnesia.system_info(:is_running)
      """)

    assert output =~ "Mnesia directory #{inspect(directory)} is not writable"
    assert output =~ "MNESIA_DIR"
    assert output =~ "bind-mount ownership and permissions"
    refute output =~ "CaseClauseError"
    assert [] = File.ls!(directory)
  end

  test "a running database in another directory is preserved and startup is refused", %{
    tmp_dir: tmp_dir
  } do
    directory = Path.join(tmp_dir, "requested")
    existing = Path.join(tmp_dir, "existing")

    output =
      run_in_vm!(directory, """
      Application.put_env(:mnesia, :dir, ~c#{inspect(existing)})
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()
      {:atomic, :ok} = :mnesia.create_table(:system_metadata,
        attributes: [:key, :value], disc_copies: [node()])
      :ok = :mnesia.dirty_write({:system_metadata, "existing", "preserved"})
      try do
        HexHub.Mnesia.init()
      rescue
        error in RuntimeError -> IO.puts("STARTUP_ERROR: " <> Exception.message(error))
      end
      :yes = :mnesia.system_info(:is_running)
      true = Path.expand(to_string(:mnesia.system_info(:directory))) == #{inspect(existing)}
      true = Application.get_env(:mnesia, :dir) == ~c#{inspect(existing)}
      [{:system_metadata, "existing", "preserved"}] =
        :mnesia.dirty_read(:system_metadata, "existing")
      :stopped = :mnesia.stop()
      """)

    assert output =~ "Mnesia is already running in #{inspect(existing)}"
    assert output =~ "Refusing to switch directories"
    refute File.exists?(directory)
  end

  test "existing memory tables are persisted without losing their records", %{tmp_dir: tmp_dir} do
    directory = Path.join(tmp_dir, "metadata")

    run_in_vm!(directory, """
    Application.put_env(:mnesia, :dir, ~c#{inspect(directory)})
    :ok = :mnesia.create_schema([node()])
    :ok = :mnesia.start()
    {:atomic, :ok} = :mnesia.create_table(:system_metadata,
      attributes: [:key, :value], ram_copies: [node()])
    :ok = :mnesia.dirty_write({:system_metadata, "legacy", "preserved"})
    :ok = HexHub.Mnesia.init()
    :disc_copies = :mnesia.table_info(:system_metadata, :storage_type)
    :ok = :mnesia.sync_log()
    :stopped = :mnesia.stop()
    """)

    run_in_vm!(directory, """
    :ok = HexHub.Mnesia.init()
    [{:system_metadata, "legacy", "preserved"}] =
      :mnesia.dirty_read(:system_metadata, "legacy")
    :stopped = :mnesia.stop()
    """)
  end

  test "a failed persistence conversion is reported instead of accepting a memory table", %{
    tmp_dir: tmp_dir
  } do
    directory = Path.join(tmp_dir, "metadata")

    output =
      run_in_vm!(directory, """
      Application.put_env(:mnesia, :dir, ~c#{inspect(directory)})
      :ok = :mnesia.start()
      {:users, options} = List.keyfind(HexHub.Database.Schema.definitions(), :users, 0)
      {:atomic, :ok} = :mnesia.create_table(:users,
        attributes: options[:attributes], ram_copies: [node()])
      record = {:users, "preserved", "user@example.com", nil, nil, false, [], false, nil, nil, nil}
      :ok = :mnesia.dirty_write(record)
      try do
        HexHub.Mnesia.migrate_to_disc_copies()
      rescue
        error in RuntimeError -> IO.puts("STARTUP_ERROR: " <> Exception.message(error))
      end
      :ram_copies = :mnesia.table_info(:users, :storage_type)
      [^record] = :mnesia.dirty_read(:users, "preserved")
      :stopped = :mnesia.stop()
      """)

    assert output =~ "Failed to persist Mnesia table users"
  end

  # Mnesia and its application environment are global to a BEAM instance.
  # Separate VMs exercise startup without stopping the suite's metadata database.
  defp run_in_vm!(directory, body) do
    code = """
    Application.put_env(:hex_hub, :database_backend, :mnesia)
    Application.put_env(:hex_hub, :mnesia_dir, #{inspect(directory)})
    #{body}
    """

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2", "-pa", Application.app_dir(:hex_hub, "ebin"), "-e", code],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
  end
end
