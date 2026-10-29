defmodule HexHub.DatabaseTest do
  use ExUnit.Case, async: false

  alias HexHub.Database

  setup do
    key = "database_test_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Database.transaction(fn ->
        Database.delete({:system_metadata, key})
        Database.delete({:system_metadata, {key, "nested"}})
        Database.delete({:package_owners, key})
      end)
    end)

    %{key: key}
  end

  test "set records preserve metadata types and overwrite by key", %{key: key} do
    value = %{timestamp: DateTime.utc_now(), source: :local, bytes: <<0, 255, 128>>}
    record = {:system_metadata, key, value}
    assert {:atomic, :ok} = Database.transaction(fn -> Database.write(record) end)
    assert [^record] = Database.dirty_read(:system_metadata, key)

    assert {:atomic, :ok} =
             Database.sync_transaction(fn ->
               Database.write({:system_metadata, key, :updated})
             end)

    assert [{:system_metadata, ^key, :updated}] = Database.dirty_read(:system_metadata, key)
  end

  test "bag records retain owners, deduplicate objects, and delete one object", %{key: key} do
    first = {:package_owners, key, "first", "full", DateTime.utc_now()}
    second = {:package_owners, key, "second", "full", DateTime.utc_now()}

    assert {:atomic, :ok} =
             Database.transaction(fn ->
               Database.write(first)
               Database.write(first)
               Database.write(second)
             end)

    assert Enum.sort(Database.dirty_read(:package_owners, key)) == Enum.sort([first, second])
    assert {:atomic, :ok} = Database.transaction(fn -> Database.delete_object(first) end)
    assert [^second] = Database.dirty_read(:package_owners, key)

    assert {:atomic, :ok} =
             Database.transaction(fn -> Database.delete({:package_owners, key}) end)

    assert [] = Database.dirty_read(:package_owners, key)
  end

  test "aborting a transaction rolls back every write", %{key: key} do
    assert {:aborted, :cancelled} =
             Database.transaction(fn ->
               Database.write({:system_metadata, key, "first"})
               Database.write({:system_metadata, {key, "nested"}, "second"})
               Database.abort(:cancelled)
             end)

    assert [] = Database.dirty_read(:system_metadata, key)
    assert [] = Database.dirty_read(:system_metadata, {key, "nested"})
  end

  test "exceptions roll back changes and leave the connection usable", %{key: key} do
    assert {:aborted, _reason} =
             Database.transaction(fn ->
               Database.write({:system_metadata, key, "discarded"})
               raise "transaction failed"
             end)

    assert [] = Database.dirty_read(:system_metadata, key)

    assert {:atomic, :ok} =
             Database.transaction(fn -> Database.write({:system_metadata, key, "committed"}) end)

    assert [{:system_metadata, ^key, "committed"}] = Database.dirty_read(:system_metadata, key)
  end

  test "nested transactions use the same connection and commit together", %{key: key} do
    assert {:atomic, {:atomic, :ok}} =
             Database.transaction(fn ->
               Database.write({:system_metadata, key, "outer"})

               Database.transaction(fn ->
                 assert [{:system_metadata, ^key, "outer"}] = Database.read(:system_metadata, key)
                 Database.write({:system_metadata, key, "inner"})
               end)
             end)

    assert [{:system_metadata, ^key, "inner"}] = Database.dirty_read(:system_metadata, key)
  end

  test "match specifications support composite keys and projections", %{key: key} do
    assert :ok = Database.dirty_write({:system_metadata, {key, "nested"}, 7})

    assert [{:system_metadata, {^key, "nested"}, 7}] =
             Database.dirty_match_object({:system_metadata, {key, :_}, :_})

    assert {:atomic, [7]} =
             Database.transaction(fn ->
               Database.select(:system_metadata, [
                 {{:system_metadata, {key, :_}, :"$1"}, [{:>, :"$1", 5}], [:"$1"]}
               ])
             end)
  end

  test "a nested abort preserves outer writes and discards inner writes", %{key: key} do
    assert {:atomic, {:aborted, :cancelled}} =
             Database.transaction(fn ->
               Database.write({:system_metadata, key, "outer"})

               result =
                 Database.transaction(fn ->
                   Database.write({:system_metadata, key, "inner"})
                   Database.abort(:cancelled)
                 end)

               assert [{:system_metadata, ^key, "outer"}] = Database.read(:system_metadata, key)
               result
             end)

    assert [{:system_metadata, ^key, "outer"}] = Database.dirty_read(:system_metadata, key)
  end

  test "a nested exception rolls back to the savepoint and allows outer work", %{key: key} do
    assert {:atomic, :ok} =
             Database.transaction(fn ->
               Database.write({:system_metadata, key, "outer"})

               assert {:aborted, _reason} =
                        Database.transaction(fn ->
                          Database.write({:system_metadata, key, "inner"})
                          raise "inner failed"
                        end)

               assert [{:system_metadata, ^key, "outer"}] = Database.read(:system_metadata, key)
               Database.write({:system_metadata, key, "continued"})
             end)

    assert [{:system_metadata, ^key, "continued"}] = Database.dirty_read(:system_metadata, key)
  end

  test "an outer abort also rolls back successful nested writes", %{key: key} do
    assert {:aborted, :cancelled} =
             Database.transaction(fn ->
               assert {:atomic, :ok} =
                        Database.transaction(fn ->
                          Database.write({:system_metadata, key, "inner"})
                        end)

               Database.abort(:cancelled)
             end)

    assert [] = Database.dirty_read(:system_metadata, key)
  end

  test "concurrent read-modify-write transactions do not lose updates", %{key: key} do
    :ok = Database.dirty_write({:system_metadata, key, 0})

    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          Database.transaction(fn ->
            [{:system_metadata, ^key, count}] = Database.read(:system_metadata, key)
            Process.sleep(1)
            Database.write({:system_metadata, key, count + 1})
          end)
        end,
        max_concurrency: 8
      )
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, {:atomic, :ok}}))
    assert [{:system_metadata, ^key, 8}] = Database.dirty_read(:system_metadata, key)
  end

  test "health checks report the selected backend" do
    backend = Database.backend()

    assert %{status: :healthy, checks: %{^backend => %{healthy: true}}} =
             HexHub.HealthCheck.ready()

    if backend == :postgresql do
      assert :no = :mnesia.system_info(:is_running)
      assert %{backend: :postgresql, running: :yes} = HexHub.Clustering.get_cluster_status()
      assert {:error, :requires_mnesia} = HexHub.Clustering.join_cluster("ignored@localhost")
      assert {:error, :requires_mnesia} = HexHub.Clustering.leave_cluster()
    end
  end
end
