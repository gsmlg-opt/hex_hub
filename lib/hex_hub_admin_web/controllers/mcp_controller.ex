defmodule HexHubAdminWeb.MCPController do
  use HexHubAdminWeb, :controller

  alias HexHub.MCP
  alias HexHub.MCP.{Handler, LogStore}

  def info(conn, _params) do
    config = MCP.config()
    enabled = MCP.enabled?()

    server_status =
      if enabled do
        Handler.health_check()
      else
        %{status: "disabled", tool_count: 0, stats: Handler.get_stats()}
      end

    tools =
      if enabled do
        Handler.get_tool_status()
      else
        []
      end

    tokens =
      case HexHub.ApiKeys.list_all_keys() do
        {:ok, keys} -> keys
        _ -> []
      end

    render(conn, :info,
      config: config,
      enabled: enabled,
      server_status: server_status,
      tools: tools,
      tokens: tokens
    )
  end

  def clients(conn, _params) do
    enabled = MCP.enabled?()

    stats =
      if enabled do
        %{
          total_requests: 0,
          active_connections: 0,
          success_rate: 1.0,
          avg_response_time: 0
        }
      else
        %{
          total_requests: 0,
          active_connections: 0,
          success_rate: 0.0,
          avg_response_time: 0
        }
      end

    render(conn, :clients, enabled: enabled, stats: stats)
  end

  def logs(conn, params) do
    enabled = MCP.enabled?()
    page = String.to_integer(Map.get(params, "page", "1"))
    per_page = 30
    offset = (page - 1) * per_page

    {logs, total} =
      if enabled do
        {:ok, entries, total} = LogStore.list_logs(limit: per_page, offset: offset)
        {entries, total}
      else
        {[], 0}
      end

    total_pages = max(ceil(total / per_page), 1)

    render(conn, :logs,
      enabled: enabled,
      logs: logs,
      page: page,
      total: total,
      total_pages: total_pages
    )
  end

  def toggle_auth(conn, %{"require_auth" => value}) do
    require_auth = value == "true"
    Handler.update_config(require_auth: require_auth)

    conn
    |> put_flash(:info, "MCP authentication #{if require_auth, do: "enabled", else: "disabled"}.")
    |> redirect(to: ~p"/mcp")
  end

  def clear_logs(conn, _params) do
    LogStore.clear()

    conn
    |> put_flash(:info, "MCP logs cleared.")
    |> redirect(to: ~p"/mcp/logs")
  end

  def inspector(conn, _params) do
    enabled = MCP.enabled?()

    tools =
      if enabled do
        Handler.get_tool_status()
      else
        []
      end

    render(conn, :inspector, enabled: enabled, tools: tools, result: nil, action: nil)
  end

  def run_inspection(conn, %{"action" => action} = params) do
    enabled = MCP.enabled?()

    tools =
      if enabled do
        Handler.get_tool_status()
      else
        []
      end

    result =
      if enabled do
        run_mcp_action(action, params)
      else
        %{error: "MCP server is disabled"}
      end

    render(conn, :inspector, enabled: enabled, tools: tools, result: result, action: action)
  end

  defp run_mcp_action("initialize", _params) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "HexHub Inspector", "version" => "1.0.0"}
      }
    }

    execute_mcp_request(request)
  end

  defp run_mcp_action("list_tools", _params) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list",
      "params" => %{}
    }

    execute_mcp_request(request)
  end

  defp run_mcp_action("call_tool", %{"tool_name" => tool_name, "arguments" => arguments}) do
    args =
      case Jason.decode(arguments) do
        {:ok, decoded} -> decoded
        {:error, _} -> %{}
      end

    request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call/#{tool_name}",
      "params" => %{"arguments" => args}
    }

    execute_mcp_request(request)
  end

  defp run_mcp_action("call_tool", %{"tool_name" => tool_name}) do
    run_mcp_action("call_tool", %{"tool_name" => tool_name, "arguments" => "{}"})
  end

  defp run_mcp_action("health_check", _params) do
    %{ok: Handler.health_check()}
  end

  defp run_mcp_action(_, _params) do
    %{error: "Unknown action"}
  end

  defp execute_mcp_request(request) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        Handler.handle_request(request)
      rescue
        e -> {:error, %{"error" => %{"message" => Exception.message(e)}}}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, response} -> %{ok: response, duration_ms: duration, request: request}
      {:error, response} -> %{error: response, duration_ms: duration, request: request}
    end
  end
end
