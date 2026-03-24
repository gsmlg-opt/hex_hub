defmodule HexHub.MCP.HandlerTest do
  use ExUnit.Case, async: false
  alias HexHub.MCP.Handler

  import Mox

  setup :verify_on_exit!

  describe "handle_request/2" do
    test "handles valid initialize request" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => "test-1",
        "params" => %{
          "protocolVersion" => "2024-11-05",
          "capabilities" => %{},
          "clientInfo" => %{
            "name" => "test-client",
            "version" => "1.0.0"
          }
        }
      }

      {:ok, response} = Handler.handle_request(request)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-1"
      assert Map.has_key?(response, "result")
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert Map.has_key?(response["result"], "capabilities")
      assert Map.has_key?(response["result"], "serverInfo")
    end

    test "handles tools/list request" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => "test-2"
      }

      {:ok, response} = Handler.handle_request(request)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-2"
      assert Map.has_key?(response, "result")
      assert Map.has_key?(response["result"], "tools")
      assert is_list(response["result"]["tools"])
    end

    test "handles invalid JSON" do
      invalid_request = "invalid json"

      {:error, response} = Handler.handle_request(invalid_request)
      assert response["jsonrpc"] == "2.0"
      assert response["error"]["code"] == -32700
      assert response["error"]["message"] == "Parse error"
    end

    test "handles missing required fields" do
      invalid_request = %{
        "jsonrpc" => "2.0"
        # Missing "method" field
      }

      {:error, response} = Handler.handle_request(invalid_request)
      assert response["jsonrpc"] == "2.0"
      assert response["error"]["code"] == -32600
      assert response["error"]["message"] == "Invalid Request"
    end

    test "handles invalid JSON-RPC version" do
      invalid_request = %{
        "jsonrpc" => "1.0",
        "method" => "initialize",
        "id" => "test-1"
      }

      {:error, response} = Handler.handle_request(invalid_request)
      assert response["error"]["code"] in [-32600, -32602]
    end

    test "handles method not found" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "unknown_method",
        "id" => "test-1"
      }

      {:error, response} = Handler.handle_request(request)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-1"
      assert response["error"]["code"] == -32601
      assert response["error"]["message"] == "Method not found"
    end

    test "handles tool call with valid method" do
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

      # This may return error if tool execution fails, but should not be a parsing error
      result = Handler.handle_request(request)

      case result do
        {:ok, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-3"
          assert Map.has_key?(response, "result")

        {:error, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-3"
          # Should not be a parsing error
          assert response["error"]["code"] != -32700
          assert response["error"]["code"] != -32600
      end
    end

    test "handles tool call with missing arguments" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call/search_packages",
        "id" => "test-4",
        "params" =>
          %{
            # Missing "arguments" field
          }
      }

      result = Handler.handle_request(request)

      case result do
        {:ok, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-4"

        {:error, response} ->
          assert response["jsonrpc"] == "2.0"
          assert response["id"] == "test-4"
          # Invalid params or server error
          assert response["error"]["code"] in [-32602, -32000]
      end
    end
  end

  describe "init/1" do
    test "initializes handler with default config" do
      assert {:ok, state} = Handler.init()
      assert Map.has_key?(state, :config)
    end

    test "initializes handler with custom config" do
      custom_config = [enabled: true, rate_limit: 500]
      assert {:ok, state} = Handler.init(config: custom_config)
      assert state.config == custom_config
    end
  end

  describe "health_check/0" do
    test "returns health status" do
      health = Handler.health_check()
      assert Map.has_key?(health, :status)
      assert Map.has_key?(health, :timestamp)
      assert Map.has_key?(health, :server_status)
      assert Map.has_key?(health, :tool_count)
      assert Map.has_key?(health, :stats)
      assert health.status in ["healthy", "degraded", "unhealthy"]
      assert %DateTime{} = health.timestamp
    end
  end

  describe "get_stats/0" do
    test "returns handler statistics" do
      stats = Handler.get_stats()
      assert Map.has_key?(stats, :total_requests)
      assert Map.has_key?(stats, :success_rate)
      assert Map.has_key?(stats, :avg_response_time)
      assert Map.has_key?(stats, :error_breakdown)
      assert is_number(stats.total_requests)
      assert is_number(stats.success_rate)
      assert is_number(stats.avg_response_time)
      assert is_map(stats.error_breakdown)
    end
  end

  describe "get_config/0" do
    test "returns current configuration" do
      config = Handler.get_config()
      assert is_list(config)
    end
  end

  describe "update_config/1" do
    test "updates configuration" do
      # Get current config
      original_config = Handler.get_config()

      # Update config
      new_config = [test_option: true]
      assert {:ok, updated_config} = Handler.update_config(new_config)
      assert Keyword.get(updated_config, :test_option) == true

      # Verify the change was applied
      current_config = Handler.get_config()
      assert Keyword.get(current_config, :test_option) == true

      # Restore original config
      Application.put_env(:hex_hub, :mcp, original_config)
    end
  end

  describe "get_tool_status/0" do
    test "returns tool status information" do
      tool_status = Handler.get_tool_status()
      assert is_list(tool_status)

      if tool_status != [] do
        tool = List.first(tool_status)
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :description)
        assert Map.has_key?(tool, :enabled)
        assert Map.has_key?(tool, :last_used)
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_boolean(tool.enabled)
      end
    end
  end

  describe "reset_stats/0" do
    test "resets statistics" do
      assert :ok = Handler.reset_stats()
    end
  end

  describe "toggle_tool/2" do
    test "toggles tool enable/disable" do
      assert :ok = Handler.toggle_tool("test_tool", true)
      assert :ok = Handler.toggle_tool("test_tool", false)
    end
  end

  describe "graceful_shutdown/0" do
    test "initiates graceful shutdown" do
      assert :ok = Handler.graceful_shutdown()
    end
  end

  describe "reload/0" do
    test "reloads handler configuration" do
      result = Handler.reload()
      assert result == :ok or match?({:error, _}, result)
    end
  end
end
