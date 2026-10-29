defmodule HexHubWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Metadata tables are cleared before each test for both database backends.
  Tests using this case must run synchronously because they share application
  configuration, caches, and metadata tables.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint HexHubWeb.Endpoint

      use HexHubWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import HexHubWeb.ConnCase
      import HexHub.TestHelpers
    end
  end

  setup _tags do
    # Clear metadata tables before each test
    HexHub.Database.reset_tables()

    # Clear Users test store
    HexHub.Users.reset_test_store()

    # Ensure storage is reset to local for test isolation
    Application.put_env(:hex_hub, :storage_type, :local)
    Application.put_env(:hex_hub, :storage_path, "priv/test_storage")

    # Clear test storage
    test_storage_path = "priv/test_storage"

    if File.exists?(test_storage_path) do
      File.rm_rf!(test_storage_path)
      File.mkdir_p!(test_storage_path)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
