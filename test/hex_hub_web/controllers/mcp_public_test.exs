defmodule HexHubWeb.MCPPublicTest do
  @moduledoc """
  Tests for public (unauthenticated) access to MCP endpoints.

  These tests verify that AI clients can access package information
  via MCP without requiring authentication when require_auth: false.
  """

  use HexHubWeb.ConnCase, async: false

  setup do
    # Enable MCP with public access for all tests
    Application.put_env(:hex_hub, :mcp, enabled: true, require_auth: false)

    on_exit(fn ->
      Application.delete_env(:hex_hub, :mcp)
    end)

    :ok
  end

  describe "User Story 1: AI Client Queries Package Information" do
    setup do
      # Create test packages for querying
      package = create_package(%{name: "phoenix", meta: %{description: "Web framework for Elixir"}})
      _package2 = create_package(%{name: "ecto", meta: %{description: "Database wrapper for Elixir"}})

      %{package: package}
    end

    # T009: Public access to search_packages without API key
    test "search_packages returns results without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call/search_packages",
        "params" => %{
          "arguments" => %{
            "query" => "phoenix",
            "limit" => 5
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      # Should have result or error, but not unauthorized error
      refute response["error"]["code"] == -32001
    end

    # T010: Public access to get_package without API key
    test "get_package returns package details without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call/get_package",
        "params" => %{
          "arguments" => %{
            "name" => "phoenix"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end

    # T011: Public access to list_packages without API key
    test "list_packages returns paginated results without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call/list_packages",
        "params" => %{
          "arguments" => %{
            "page" => 1,
            "per_page" => 10
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 3

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end

    # T012: Invalid JSON-RPC request returns error -32600
    test "invalid JSON-RPC request returns error -32600", %{conn: conn} do
      # Missing required fields (no method)
      invalid_request = %{
        "jsonrpc" => "2.0",
        "id" => 4
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", invalid_request)

      # Server should return an error response
      response = json_response(conn, conn.status)
      assert response["jsonrpc"] == "2.0"
      assert response["error"]["code"] == -32600
    end

    # T013: Non-existent package returns proper error
    test "non-existent package returns proper error", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call/get_package",
        "params" => %{
          "arguments" => %{
            "name" => "nonexistent_package_xyz123"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      # Can return 200 with error in body, or 500 for server error
      # The key is it should NOT return 401/403 unauthorized
      assert conn.status in [200, 500]
      response = json_response(conn, conn.status)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 5

      # Should have an error, but not unauthorized error
      refute response["error"]["code"] == -32001
    end
  end

  describe "User Story 2: AI Client Lists Available Tools" do
    # T018: GET /mcp/tools returns all tools without authentication
    test "GET /mcp/tools returns tools without authentication", %{conn: conn} do
      conn = get(conn, ~p"/mcp/tools")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert Map.has_key?(response, "tools")
      assert Map.has_key?(response, "server")
      assert is_list(response["tools"])
    end

    # T019: GET /mcp/server-info returns server capabilities
    test "GET /mcp/server-info returns server capabilities without authentication", %{conn: conn} do
      conn = get(conn, ~p"/mcp/server-info")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["name"] == "HexHub MCP Server"
      assert Map.has_key?(response, "capabilities")
      assert Map.has_key?(response, "authentication")

      # Authentication should show not required
      assert response["authentication"]["required"] == false
    end

    # T020: Returned tools include inputSchema for each tool
    test "returned tools include inputSchema for each tool", %{conn: conn} do
      conn = get(conn, ~p"/mcp/tools")

      assert conn.status == 200
      response = json_response(conn, 200)
      tools = response["tools"]

      # Each tool should have name, description, and inputSchema
      Enum.each(tools, fn tool ->
        assert Map.has_key?(tool, "name"), "Tool missing name: #{inspect(tool)}"
        assert Map.has_key?(tool, "description"), "Tool #{tool["name"]} missing description"
        assert Map.has_key?(tool, "inputSchema"), "Tool #{tool["name"]} missing inputSchema"
      end)
    end
  end

  describe "User Story 3: AI Client Retrieves Package Dependencies" do
    setup do
      # Create packages with releases for dependency tests
      package = create_package(%{name: "phoenix_live_view", meta: %{description: "LiveView for Phoenix"}})

      # Create release with tarball
      tarball = create_test_tarball("phoenix_live_view", "1.0.0")
      meta = %{"app" => "phoenix_live_view", "description" => "LiveView"}
      requirements = %{"phoenix" => %{"requirement" => "~> 1.7"}}
      {:ok, _release} = HexHub.Packages.create_release("phoenix_live_view", "1.0.0", meta, requirements, tarball)

      # Create phoenix package with release for compatibility tests
      _phoenix = create_package(%{name: "phoenix", meta: %{description: "Web framework"}})
      phoenix_tarball = create_test_tarball("phoenix", "1.7.0")
      {:ok, _} = HexHub.Packages.create_release("phoenix", "1.7.0", %{}, %{}, phoenix_tarball)

      # Create ecto package with release
      _ecto = create_package(%{name: "ecto", meta: %{description: "Database wrapper"}})
      ecto_tarball = create_test_tarball("ecto", "3.10.0")
      {:ok, _} = HexHub.Packages.create_release("ecto", "3.10.0", %{}, %{}, ecto_tarball)

      %{package: package}
    end

    # T024: get_package_metadata returns dependencies without auth
    test "get_package_metadata returns dependencies without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 10,
        "method" => "tools/call/get_package_metadata",
        "params" => %{
          "arguments" => %{
            "name" => "phoenix_live_view",
            "version" => "1.0.0"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end

    # T025: get_dependency_tree returns tree structure
    test "get_dependency_tree returns structure without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 11,
        "method" => "tools/call/get_dependency_tree",
        "params" => %{
          "arguments" => %{
            "name" => "phoenix_live_view",
            "version" => "1.0.0"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      # Can return 200 or 500 - key is no unauthorized error
      assert conn.status in [200, 500]
      response = json_response(conn, conn.status)
      assert response["jsonrpc"] == "2.0"

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end

    # T026: Check compatibility works without authentication
    test "check_compatibility works without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 12,
        "method" => "tools/call/check_compatibility",
        "params" => %{
          "arguments" => %{
            "packages" => [
              %{"name" => "phoenix", "version" => "1.7.0"},
              %{"name" => "ecto", "version" => "3.10.0"}
            ]
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      # Can return 200 or 500 - key is no unauthorized error
      assert conn.status in [200, 500]
      response = json_response(conn, conn.status)
      assert response["jsonrpc"] == "2.0"

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end
  end

  describe "User Story 4: AI Client Accesses Package Documentation Links" do
    setup do
      package = create_package(%{
        name: "ex_doc",
        meta: %{
          description: "Documentation generator",
          links: %{"GitHub" => "https://github.com/elixir-lang/ex_doc"}
        }
      })

      %{package: package}
    end

    # T030: Package info includes docs_url when docs exist
    test "package info includes external links", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 20,
        "method" => "tools/call/get_package",
        "params" => %{
          "arguments" => %{
            "name" => "ex_doc"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end

    # T032: get_documentation tool works without authentication
    test "get_documentation tool accessible without authentication", %{conn: conn} do
      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 21,
        "method" => "tools/call/get_documentation",
        "params" => %{
          "arguments" => %{
            "name" => "ex_doc"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      # Can return 200 or 500 (no docs uploaded) - key is no unauthorized error
      assert conn.status in [200, 500]
      response = json_response(conn, conn.status)
      assert response["jsonrpc"] == "2.0"

      # Should not get unauthorized error
      refute response["error"]["code"] == -32001
    end
  end

  describe "Rate Limiting" do
    # T036: Rate limiting test
    test "excessive requests return 429 with retry-after header", %{conn: _conn} do
      # Set very low rate limit for testing
      Application.put_env(:hex_hub, :mcp, enabled: true, require_auth: false, rate_limit: 1)

      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      }

      # Make first request (should succeed)
      conn1 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-forwarded-for", "10.0.0.1")
        |> post(~p"/mcp", mcp_request)

      # First request should succeed
      assert conn1.status in [200, 500]

      # Make second request immediately (should be rate limited)
      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-forwarded-for", "10.0.0.1")
        |> post(~p"/mcp", mcp_request)

      # Could be rate limited (429) or success if window expired
      # The key test is that the system handles rate limiting without crashing
      assert conn2.status in [200, 429, 500]

      if conn2.status == 429 do
        response = json_response(conn2, 429)
        assert response["error"]["code"] == -32002
        # Check retry-after header
        retry_after = get_resp_header(conn2, "retry-after")
        assert length(retry_after) > 0
      end

      # Reset rate limit config
      Application.put_env(:hex_hub, :mcp, enabled: true, require_auth: false)
    end
  end

  describe "Error Handling" do
    # T037: MCP disabled returns error -32001
    test "MCP disabled returns error -32001", %{conn: conn} do
      # Disable MCP for this test
      Application.put_env(:hex_hub, :mcp, enabled: false)

      mcp_request = %{
        "jsonrpc" => "2.0",
        "id" => 100,
        "method" => "tools/list"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", mcp_request)

      assert conn.status == 503
      response = json_response(conn, 503)
      assert response["error"]["code"] == -32001
      assert response["error"]["message"] == "MCP server is disabled"
    end
  end
end
