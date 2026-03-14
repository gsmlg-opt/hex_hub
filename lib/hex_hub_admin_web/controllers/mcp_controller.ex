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
        case LogStore.list_logs(limit: per_page, offset: offset) do
          {:ok, entries, total} -> {entries, total}
          _ -> {[], 0}
        end
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
end
