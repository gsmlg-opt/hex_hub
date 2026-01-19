defmodule HexHubWeb.MCPController do
  @moduledoc """
  HTTP controller for MCP (Model Context Protocol) requests.

  Provides HTTP endpoints for MCP clients that prefer HTTP over WebSocket
  for communication with the MCP server.
  """

  use HexHubWeb, :controller

  alias HexHub.MCP.{Handler, Server}
  alias HexHub.Telemetry

  # MCP authentication and rate limiting plugs
  plug :check_mcp_enabled when action in [:handle_request, :list_tools, :server_info]
  plug :authenticate_mcp_request when action in [:handle_request, :list_tools, :server_info]
  plug :rate_limit_mcp_request when action in [:handle_request, :list_tools, :server_info]

  @doc """
  Handle MCP JSON-RPC requests via HTTP POST.
  """
  def handle_request(conn, params) do
    start_time = System.monotonic_time(:millisecond)

    case Handler.handle_request(params, nil) do
      {:ok, response} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        conn
        |> put_resp_header("content-type", "application/json")
        |> put_resp_header("x-mcp-response-time", "#{duration}")
        |> json(response)

      {:error, response} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        Telemetry.log(:error, :mcp, "MCP HTTP request failed", %{
          duration_ms: duration,
          error: inspect(response)
        })

        status = determine_error_status(response)

        conn
        |> put_status(status)
        |> json(response)
    end
  end

  @doc """
  List available MCP tools via HTTP GET.
  """
  def list_tools(conn, _params) do
    case Server.list_tools() do
      {:ok, tools} ->
        result = %{
          tools: tools,
          server: %{
            name: "HexHub MCP Server",
            version: "1.0.0",
            capabilities: list_capabilities()
          }
        }

        conn
        |> put_resp_header("content-type", "application/json")
        |> json(result)

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "Failed to list MCP tools", %{reason: inspect(reason)})

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: %{
            code: -32000,
            message: "Failed to list tools"
          }
        })
    end
  end

  @doc """
  Get MCP server information and capabilities.
  """
  def server_info(conn, _params) do
    info = %{
      name: "HexHub MCP Server",
      version: "1.0.0",
      description: "Hex package manager MCP server for AI clients",
      capabilities: list_capabilities(),
      endpoints: %{
        websocket: websocket_url(conn),
        http: http_url(conn)
      },
      authentication: %{
        required: HexHub.MCP.require_auth?(),
        type: "Bearer token (API key)"
      },
      configuration: %{
        enabled: HexHub.MCP.enabled?(),
        websocket_path: HexHub.MCP.websocket_path(),
        rate_limit: HexHub.MCP.rate_limit()
      }
    }

    conn
    |> put_resp_header("content-type", "application/json")
    |> json(info)
  end

  @doc """
  Health check endpoint for MCP service.
  """
  def health(conn, _params) do
    health_status = Handler.health_check()

    status = if health_status.status == "healthy", do: :ok, else: :service_unavailable

    conn
    |> put_status(status)
    |> json(health_status)
  end

  # Plugs

  defp check_mcp_enabled(conn, _opts) do
    if HexHub.MCP.enabled?() do
      conn
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{
        jsonrpc: "2.0",
        id: nil,
        error: %{
          code: -32001,
          message: "MCP server is disabled"
        }
      })
      |> halt()
    end
  end

  defp authenticate_mcp_request(conn, _opts) do
    case extract_and_validate_api_key(conn) do
      :ok ->
        conn

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          jsonrpc: "2.0",
          id: nil,
          error: %{
            code: -32001,
            message: format_auth_error_message(reason)
          }
        })
        |> halt()
    end
  end

  defp rate_limit_mcp_request(conn, _opts) do
    case HexHub.MCP.Transport.check_rate_limit(conn, []) do
      :ok ->
        conn

      {:error, :rate_limited, remaining} ->
        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(remaining))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> json(%{
          jsonrpc: "2.0",
          id: nil,
          error: %{
            code: -32002,
            message: "Rate limit exceeded"
          }
        })
        |> halt()
    end
  end

  # Private helper functions

  defp extract_and_validate_api_key(conn) do
    if HexHub.MCP.require_auth?() do
      case extract_api_key(conn) do
        {:ok, api_key} ->
          validate_api_key(api_key)

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end

  defp extract_api_key(conn) do
    # Try Authorization header first
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> key] ->
        {:ok, key}

      ["Basic " <> auth_header] ->
        # Decode Base64 and check for "mcp:apikey" format
        case Base.decode64(auth_header) do
          {:ok, "mcp:" <> key} -> {:ok, key}
          _ -> {:error, :invalid_api_key}
        end

      _ ->
        # Try query parameter
        case conn.query_params do
          %{"api_key" => key} -> {:ok, key}
          _ -> {:error, :no_api_key}
        end
    end
  end

  defp validate_api_key(api_key) do
    case HexHub.ApiKeys.validate_key(api_key) do
      {:ok, _user} -> :ok
      {:error, _reason} -> {:error, :invalid_api_key}
    end
  end

  defp format_auth_error_message(reason) do
    case reason do
      :no_api_key -> "API key required"
      :invalid_api_key -> "Invalid API key"
    end
  end

  defp list_capabilities do
    [
      %{
        name: "package_management",
        description: "Search, retrieve, and manage Hex packages",
        tools: [
          "search_packages",
          "get_package",
          "list_packages",
          "get_package_metadata"
        ]
      },
      %{
        name: "release_management",
        description: "Manage package versions and releases",
        tools: [
          "list_releases",
          "get_release",
          "download_release",
          "compare_releases"
        ]
      },
      %{
        name: "documentation_access",
        description: "Access and search package documentation",
        tools: [
          "get_documentation",
          "list_documentation_versions",
          "search_documentation"
        ]
      },
      %{
        name: "dependency_resolution",
        description: "Resolve and analyze package dependencies",
        tools: [
          "resolve_dependencies",
          "get_dependency_tree",
          "check_compatibility"
        ]
      },
      %{
        name: "repository_management",
        description: "Manage package repositories",
        tools: [
          "list_repositories",
          "get_repository_info",
          "toggle_package_visibility"
        ]
      }
    ]
  end

  defp websocket_url(conn) do
    scheme = if conn.scheme == :https, do: "wss", else: "ws"
    host = conn.host
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    path = HexHub.MCP.websocket_path()

    "#{scheme}://#{host}#{port}#{path}"
  end

  defp http_url(conn) do
    scheme = "#{conn.scheme}"
    host = conn.host
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{scheme}://#{host}#{port}/mcp"
  end

  defp determine_error_status(_response) do
    # Default to internal_server_error for all error responses
    # Specific status codes can be added based on actual error response structure
    :internal_server_error
  end

  @doc """
  Log MCP HTTP request for monitoring.
  """
  def log_mcp_request(conn, params, duration, status) do
    Telemetry.log(:info, :mcp, "MCP HTTP request", %{
      method: conn.method,
      path: conn.request_path,
      ip: format_ip(conn.remote_ip),
      user_agent: get_user_agent(conn),
      method_name: Map.get(params, "method"),
      duration_ms: duration,
      status: status
    })
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp format_ip(ip), do: ip

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent | _] -> user_agent
      [] -> "unknown"
    end
  end

  @doc """
  Get MCP controller statistics.
  """
  def get_stats do
    %{
      total_requests: get_total_requests(),
      success_rate: get_success_rate(),
      avg_response_time: get_avg_response_time(),
      error_rate: get_error_rate(),
      active_connections: get_active_connections()
    }
  end

  defp get_total_requests do
    # Get total request count from telemetry
    0
  end

  defp get_success_rate do
    # Calculate success rate from telemetry data
    1.0
  end

  defp get_avg_response_time do
    # Get average response time from telemetry
    0
  end

  defp get_error_rate do
    # Calculate error rate from telemetry data
    0.0
  end

  defp get_active_connections do
    # Get active connection count
    0
  end

  @doc """
  Handle CORS preflight requests for MCP endpoints.
  """
  def options(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization")
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(:no_content, "")
  end

  @doc """
  Add CORS headers to MCP responses.
  """
  def add_cors_headers(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-credentials", "false")
  end
end
