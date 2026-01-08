defmodule HexHubAdminWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection for admin routes.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint HexHubAdminWeb.Endpoint

      use HexHubAdminWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import HexHubAdminWeb.ConnCase
      import HexHub.TestHelpers
    end
  end

  setup _tags do
    # Clear Mnesia tables before each test
    HexHub.Mnesia.reset_tables()

    # Clear Users test store
    HexHub.Users.reset_test_store()

    # Clear test storage
    test_storage_path = "priv/test_storage"

    if File.exists?(test_storage_path) do
      File.rm_rf!(test_storage_path)
      File.mkdir_p!(test_storage_path)
    end

    # Build connection for admin routes
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
      |> Plug.Test.init_test_session(%{})

    {:ok, conn: conn}
  end
end
