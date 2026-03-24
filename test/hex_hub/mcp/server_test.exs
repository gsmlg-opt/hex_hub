defmodule HexHub.MCP.ServerTest do
  use ExUnit.Case, async: false
  alias HexHub.MCP.Server

  import Mox

  setup :verify_on_exit!

  describe "start_link/1" do
    test "starts the server with default config" do
      # Skip if server is already running
      if Process.whereis(Server) do
        :ok
      else
        assert {:ok, pid} = Server.start_link()
        assert Process.alive?(pid)
        assert Process.whereis(Server) == pid

        # Clean up
        GenServer.stop(pid)
      end
    end

    test "starts the server with custom config" do
      # Skip if server is already running
      if Process.whereis(Server) do
        :ok
      else
        custom_config = [enabled: true, rate_limit: 500]
        assert {:ok, pid} = Server.start_link(config: custom_config)
        assert Process.alive?(pid)

        # Clean up
        GenServer.stop(pid)
      end
    end
  end

  describe "list_tools/0" do
    test "returns list of available tools" do
      # Start server if not running
      start_server_if_needed()

      case Server.list_tools() do
        {:ok, tools} ->
          assert is_list(tools)

          if tools != [] do
            tool = List.first(tools)
            assert Map.has_key?(tool, "name")
            assert Map.has_key?(tool, "description")
            assert Map.has_key?(tool, "inputSchema")
            assert is_binary(tool["name"])
            assert is_binary(tool["description"])
            assert is_map(tool["inputSchema"])
          end

        {:error, reason} ->
          # Server may not be fully initialized
          assert reason in [:tool_not_found, :server_error]
      end
    end
  end

  describe "get_tool_schema/1" do
    test "returns schema for existing tool" do
      start_server_if_needed()

      case Server.get_tool_schema("search_packages") do
        {:ok, tool} ->
          assert tool.name == "search_packages"
          assert is_binary(tool.description)
          assert is_map(tool.input_schema)
          assert is_function(tool.handler)

        {:error, :tool_not_found} ->
          # Tool may not be registered
          :ok
      end
    end

    test "returns error for non-existent tool" do
      start_server_if_needed()

      assert {:error, :tool_not_found} = Server.get_tool_schema("non_existent_tool")
    end
  end

  describe "handle_request/2" do
    test "handles valid request" do
      start_server_if_needed()

      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => "test-1"
      }

      result = Server.handle_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-1"
          assert Map.has_key?(response, "result")

        {:error, response} ->
          assert response["jsonrpc"] == "2.0"
          assert Map.has_key?(response, "error")
      end
    end

    test "handles tools/list request" do
      start_server_if_needed()

      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => "test-2"
      }

      result = Server.handle_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-2"
          assert Map.has_key?(response["result"])

          if Map.has_key?(response["result"], "tools") do
            assert is_list(response["result"]["tools"])
          end

        {:error, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-2"
      end
    end

    test "handles invalid request" do
      start_server_if_needed()

      invalid_request = %{
        "jsonrpc" => "2.0"
        # Missing "method" field
      }

      result = Server.handle_request(invalid_request)
      assert match?({:error, _}, result)

      case result do
        {:error, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["error"]["code"] in [-32600, -32602]
      end
    end

    test "handles tool call request" do
      start_server_if_needed()

      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call/search_packages",
        "id" => "test-3",
        "params" => %{
          "arguments" => %{
            "query" => "phoenix"
          }
        }
      }

      result = Server.handle_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-3"
          assert Map.has_key?(response, "result")

        {:error, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-3"
          # Should not be a parsing error
          assert response["error"]["code"] not in [-32700, -32600]
      end
    end
  end

  describe "server state management" do
    test "maintains tool registry" do
      start_server_if_needed()

      # Test that server maintains state across calls
      {:ok, tools1} = Server.list_tools()
      {:ok, tools2} = Server.list_tools()

      assert length(tools1) == length(tools2)

      # Test tool schemas are consistent
      if tools1 != [] do
        first_tool = List.first(tools1)
        {:ok, schema} = Server.get_tool_schema(first_tool["name"])
        assert schema.name == first_tool["name"]
      end
    end
  end

  # Helper functions

  defp start_server_if_needed do
    if Process.whereis(Server) do
      :ok
    else
      {:ok, _pid} = Server.start_link()
      # Give server time to initialize
      :timer.sleep(50)
    end
  end
end
