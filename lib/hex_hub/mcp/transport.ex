defmodule HexHub.MCP.Transport do
  @moduledoc """
  Transport layer for MCP server communication.

  Handles HTTP/WebSocket connections and manages JSON-RPC message
  transport between MCP clients and the server.
  """

  alias HexHub.MCP.Server
  alias HexHub.Telemetry

  @doc """
  Initialize the transport layer.
  """
  def init(opts \\ []) do
    config = Keyword.get(opts, :config, HexHub.MCP.config())
    Telemetry.log(:info, :mcp, "Initializing MCP transport", %{config: inspect(config)})
    {:ok, %{config: config}}
  end

  @doc """
  Handle WebSocket connection initialization.
  """
  def websocket_init(_transport, state) do
    Telemetry.log(:debug, :mcp, "MCP WebSocket connection established")
    {:ok, state}
  end

  @doc """
  Handle incoming WebSocket messages.
  """
  def websocket_handle({:text, message}, state) do
    Telemetry.log(:debug, :mcp, "Received MCP message", %{
      preview: String.slice(message, 0, 100)
    })

    case Server.handle_request(message, state) do
      {:ok, response} ->
        response_json = Jason.encode!(response)
        {:reply, {:text, response_json}, state}

      {:error, reason} ->
        error_response = build_error_response(reason)
        error_json = Jason.encode!(error_response)
        {:reply, {:text, error_json}, state}
    end
  end

  def websocket_handle({:binary, data}, state) do
    # Handle binary messages (if needed)
    websocket_handle({:text, data}, state)
  end

  @doc """
  Handle WebSocket connection termination.
  """
  def websocket_info(_info, state) do
    {:ok, state}
  end

  @doc """
  Handle HTTP POST requests for JSON-RPC.
  """
  def handle_http_request(_conn, params) do
    request_json = Jason.encode!(params)

    case Server.handle_request(request_json, nil) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, build_error_response(reason)}
    end
  end

  @doc """
  Validate and authenticate incoming requests.
  """
  def authenticate_request(conn, _opts) do
    if HexHub.MCP.require_auth?() do
      case extract_api_key(conn) do
        {:ok, api_key} ->
          validate_api_key(api_key)

        {:error, _} ->
          {:error, :unauthorized}
      end
    else
      :ok
    end
  end

  @doc """
  Apply rate limiting to MCP requests based on client IP.

  Uses Mnesia rate limit tables with key prefix "mcp:ip:" for MCP-specific tracking.
  Returns :ok if within limits, {:error, :rate_limited, remaining_seconds} if exceeded.
  """
  def check_rate_limit(conn, _opts) do
    ip = get_client_ip(conn)
    key = "mcp:ip:#{ip}"
    # MCP rate limit: requests per minute (from config, default 100)
    {limit, window} = get_mcp_rate_limit()

    case do_check_rate_limit(key, limit, window) do
      :ok ->
        increment_rate_limit_counter(key)
        :ok

      {:error, remaining} ->
        # Emit telemetry event for rate limiting
        :telemetry.execute(
          [:hex_hub, :mcp, :rate_limited],
          %{count: 1},
          %{ip: ip, remaining_seconds: remaining}
        )

        Telemetry.log(:warning, :mcp, "MCP rate limit exceeded", %{
          ip: ip,
          key: key,
          retry_after: remaining
        })

        {:error, :rate_limited, remaining}
    end
  end

  defp get_client_ip(conn) do
    # Try to get real IP from headers first (for proxied requests)
    forwarded_for = Plug.Conn.get_req_header(conn, "x-forwarded-for")

    case forwarded_for do
      [ips | _] ->
        ips
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> Tuple.to_list()
        |> Enum.join(".")
    end
  end

  defp get_mcp_rate_limit do
    # Get rate limit from config, default to 100 requests per minute
    rate_per_hour = HexHub.MCP.rate_limit()
    # Convert to per-minute for more granular control
    rate_per_minute = max(div(rate_per_hour, 60), 1)
    # limit, window_in_seconds
    {rate_per_minute, 60}
  end

  defp do_check_rate_limit(key, limit, window) do
    now = System.system_time(:second)
    window_start = now - window

    case :mnesia.transaction(fn ->
           case :mnesia.read({:rate_limit, key}) do
             [{:rate_limit, ^key, _type, _id, count, start, _updated}]
             when start > window_start ->
               if count >= limit do
                 # Calculate remaining time until window resets
                 remaining = start + window - now
                 {:error, remaining}
               else
                 :ok
               end

             _ ->
               # No recent activity or window expired
               :ok
           end
         end) do
      {:atomic, result} -> result
      # Allow request on Mnesia error (fail-open)
      {:aborted, _reason} -> :ok
    end
  end

  defp increment_rate_limit_counter(key) do
    now = System.system_time(:second)

    :mnesia.transaction(fn ->
      case :mnesia.read({:rate_limit, key}) do
        [{:rate_limit, ^key, type, id, count, start, _updated}] ->
          :mnesia.write({
            :rate_limit,
            key,
            type,
            id,
            count + 1,
            start,
            DateTime.utc_now()
          })

        [] ->
          # Create new counter with MCP type
          :mnesia.write({
            :rate_limit,
            key,
            :mcp,
            key,
            1,
            now,
            DateTime.utc_now()
          })
      end
    end)
  end

  # Private functions

  defp build_error_response({:error, reason}) do
    %{
      jsonrpc: "2.0",
      id: nil,
      error: %{
        code: -32000,
        message: "Server error: #{inspect(reason)}"
      }
    }
  end

  defp build_error_response(reason) when is_atom(reason) do
    error_codes = %{
      :unauthorized => -32001,
      :rate_limited => -32002,
      :invalid_request => -32600,
      :method_not_found => -32601,
      :invalid_params => -32602,
      :internal_error => -32603
    }

    code = Map.get(error_codes, reason, -32000)

    message =
      case reason do
        :unauthorized -> "Unauthorized"
        :rate_limited -> "Rate limit exceeded"
        :invalid_request -> "Invalid request"
        :method_not_found -> "Method not found"
        :invalid_params -> "Invalid parameters"
        :internal_error -> "Internal server error"
        _ -> "Unknown error"
      end

    %{
      jsonrpc: "2.0",
      id: nil,
      error: %{
        code: code,
        message: message
      }
    }
  end

  defp extract_api_key(conn) do
    # Try to extract API key from Authorization header
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key] -> {:ok, key}
      ["Basic " <> auth] -> decode_basic_auth(auth)
      _ -> extract_from_query_params(conn)
    end
  end

  defp get_req_header(conn, key) do
    # Phoenix.Conn behavior for getting headers
    case Plug.Conn.get_req_header(conn, key) do
      [] -> []
      headers -> headers
    end
  end

  defp decode_basic_auth(auth) do
    case Base.decode64(auth) do
      {:ok, "mcp:" <> key} -> {:ok, key}
      {:ok, _} -> {:error, :invalid_auth_format}
    end
  end

  defp extract_from_query_params(conn) do
    # Fallback to query parameters
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params do
      %{"api_key" => key} -> {:ok, key}
      _ -> {:error, :no_api_key}
    end
  end

  defp validate_api_key(api_key) do
    # Use existing HexHub API key validation
    case HexHub.ApiKeys.validate_key(api_key) do
      {:ok, _user} -> :ok
      {:error, _reason} -> {:error, :unauthorized}
    end
  end

  @doc """
  Get transport statistics for monitoring.
  """
  def get_stats do
    %{
      active_connections: count_active_connections(),
      total_requests: get_total_requests(),
      error_rate: calculate_error_rate(),
      avg_response_time: calculate_avg_response_time()
    }
  end

  defp count_active_connections do
    # Count active WebSocket connections
    # This would need to be implemented with proper connection tracking
    0
  end

  defp get_total_requests do
    # Get total request count from telemetry
    # This would need to be implemented with telemetry events
    0
  end

  defp calculate_error_rate do
    # Calculate error rate from telemetry data
    0.0
  end

  defp calculate_avg_response_time do
    # Calculate average response time from telemetry data
    0
  end

  @doc """
  Handle transport-level errors.
  """
  def handle_transport_error(error, state) do
    Telemetry.log(:error, :mcp, "MCP transport error", %{error: inspect(error)})

    case error do
      :connection_closed ->
        {:stop, :normal, state}

      :timeout ->
        {:stop, :timeout, state}

      :protocol_error ->
        {:stop, :protocol_error, state}

      _ ->
        {:stop, :error, state}
    end
  end

  @doc """
  Send heartbeat/ping messages to keep connections alive.
  """
  def send_heartbeat(state) do
    # Send periodic ping messages
    {:ok, state}
  end

  @doc """
  Graceful shutdown of transport layer.
  """
  def shutdown(state) do
    Telemetry.log(:info, :mcp, "Shutting down MCP transport")
    # Close all connections gracefully
    {:ok, state}
  end
end
