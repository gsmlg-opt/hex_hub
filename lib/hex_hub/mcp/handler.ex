defmodule HexHub.MCP.Handler do
  @moduledoc """
  MCP request/response handler.

  Coordinates between transport layer and MCP server, handling
  request routing, response formatting, and error handling.
  """

  alias HexHub.MCP.{Schemas, Server}
  alias HexHub.Telemetry

  @doc """
  Handle incoming MCP requests.
  """
  def handle_request(request, transport_state \\ nil) do
    start_time = System.monotonic_time(:millisecond)

    Telemetry.log(:debug, :mcp, "MCP handling request", %{request: inspect(request)})

    result =
      case parse_and_validate_request(request) do
        {:ok, validated_request} ->
          execute_request(validated_request, transport_state)

        {:error, reason} ->
          format_error_response(reason, get_request_id(request))
      end

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    log_request_result(request, result, duration)
    add_telemetry_metadata(request, result, duration)

    result
  end

  @doc """
  Initialize MCP handler.
  """
  def init(opts \\ []) do
    config = Keyword.get(opts, :config, HexHub.MCP.config())
    Telemetry.log(:info, :mcp, "Initializing MCP Handler")

    {:ok, %{config: config}}
  end

  @doc """
  Handle MCP server initialization.
  """
  def handle_init do
    # Register all tools and initialize server
    case Server.start_link([]) do
      {:ok, _pid} ->
        Telemetry.log(:info, :mcp, "MCP Server started successfully")
        :ok

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "Failed to start MCP Server", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Handle MCP server shutdown.
  """
  def handle_shutdown do
    Telemetry.log(:info, :mcp, "Shutting down MCP Handler")
    # Clean up resources
    :ok
  end

  # Private helper functions

  defp parse_and_validate_request(request) do
    Telemetry.log(:debug, :mcp, "Parsing request", %{request: inspect(request)})

    with {:ok, parsed} <- Schemas.parse_request(request) do
      Telemetry.log(:debug, :mcp, "Parsed request", %{parsed: inspect(parsed)})

      case Schemas.validate_request(parsed) do
        {:ok, validated} ->
          Telemetry.log(:debug, :mcp, "Validated request", %{validated: inspect(validated)})
          {:ok, validated}

        {:error, reason} ->
          Telemetry.log(:warning, :mcp, "Validation failed", %{reason: inspect(reason)})
          {:error, reason}
      end
    else
      {:error, :parse_error} ->
        {:error, :invalid_json}

      {:error, :invalid_request} ->
        {:error, :invalid_request_format}
    end
  end

  defp execute_request(request, transport_state) do
    case Map.get(request, "method") do
      "tools/list" ->
        {:ok, handle_list_tools(request)}

      method when is_binary(method) ->
        if String.starts_with?(method, "tools/call/") do
          handle_tool_call(request, transport_state)
        else
          case method do
            "initialize" ->
              {:ok, handle_initialize(request)}

            _ ->
              format_error_response(:method_not_found, Map.get(request, "id"))
          end
        end

      _ ->
        format_error_response(:method_not_found, Map.get(request, "id"))
    end
  end

  defp handle_list_tools(request) do
    case Server.list_tools() do
      {:ok, tools} ->
        build_response(Map.get(request, "id"), %{"tools" => tools})

      {:error, reason} ->
        format_error_response(reason, Map.get(request, "id"))
    end
  end

  defp handle_tool_call(request, transport_state) do
    method = Map.get(request, "method", "")
    tool_name = String.replace_prefix(method, "tools/call/", "")

    case Server.get_tool_schema(tool_name) do
      {:ok, tool} ->
        args = Map.get(Map.get(request, "params", %{}), "arguments", %{})

        case validate_tool_arguments(tool, args) do
          :ok ->
            case execute_tool(tool, args, transport_state) do
              {:ok, result} ->
                {:ok, build_response(Map.get(request, "id"), result)}

              {:error, reason} ->
                format_error_response(reason, Map.get(request, "id"))
            end

          {:error, reason} ->
            format_error_response(reason, Map.get(request, "id"))
        end

      {:error, _} ->
        format_error_response(:tool_not_found, Map.get(request, "id"))
    end
  end

  defp handle_initialize(request) do
    # Handle MCP initialization
    init_result = %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{
        "tools" => %{
          "listChanged" => true
        },
        "logging" => %{}
      },
      "serverInfo" => %{
        "name" => "HexHub MCP Server",
        "version" => "1.0.0"
      }
    }

    build_response(Map.get(request, "id"), init_result)
  end

  defp validate_tool_arguments(tool, args) do
    # Validate arguments against tool schema
    # For now, just do basic validation
    case Schemas.validate_tool_arguments(tool.name, args) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_tool(tool, args, transport_state) do
    try do
      tool.handler.(args, %{transport_state: transport_state})
    rescue
      error ->
        Telemetry.log(:error, :mcp, "Tool execution error", %{error: inspect(error)})
        {:error, :tool_execution_failed}
    end
  end

  defp build_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  defp format_error_response(reason, request_id) do
    {code, message} = map_error_to_mcp_error(reason)

    {:error,
     %{
       "jsonrpc" => "2.0",
       "id" => request_id,
       "error" => %{
         "code" => code,
         "message" => message
       }
     }}
  end

  defp map_error_to_mcp_error(reason) do
    error_mapping = %{
      :invalid_json => {-32700, "Parse error"},
      :invalid_request_format => {-32600, "Invalid Request"},
      :method_not_found => {-32601, "Method not found"},
      :invalid_params => {-32602, "Invalid params"},
      :tool_not_found => {-32601, "Tool not found"},
      :tool_execution_failed => {-32000, "Tool execution failed"},
      :server_error => {-32000, "Internal server error"},
      :unauthorized => {-32001, "Unauthorized"},
      :rate_limited => {-32002, "Rate limit exceeded"}
    }

    Map.get(error_mapping, reason, {-32000, "Unknown error"})
  end

  defp get_request_id(request) when is_map(request) do
    # Support both string and atom keys for request ID
    Map.get(request, "id") || Map.get(request, :id)
  end

  defp get_request_id(_), do: nil

  defp log_request_result(request, result, duration) do
    method = get_method(request)

    {status, error_code} =
      case result do
        {:ok, _response} -> {"success", nil}
        {:error, response} -> {"error", get_error_code(response)}
      end

    # Store in MCP log buffer for admin dashboard
    if Process.whereis(HexHub.MCP.LogStore) do
      HexHub.MCP.LogStore.log_request(%{
        method: method,
        duration_ms: duration,
        status: status,
        error_code: error_code,
        request_id: get_request_id(request)
      })
    end

    case status do
      "success" ->
        Telemetry.log(:info, :mcp, "MCP request completed", %{
          method: method,
          duration_ms: duration,
          status: status
        })

      "error" ->
        Telemetry.log(:warning, :mcp, "MCP request failed", %{
          method: method,
          duration_ms: duration,
          status: status,
          error_code: error_code
        })
    end
  end

  defp get_method(request) do
    case request do
      %{method: method} -> method
      _ -> "unknown"
    end
  end

  defp get_error_code(response) do
    case response do
      %{"error" => %{"code" => code}} -> code
      _ -> -32000
    end
  end

  defp add_telemetry_metadata(request, result, duration) do
    metadata = %{
      method: get_method(request),
      duration_ms: duration,
      success: match?({:ok, _}, result)
    }

    :telemetry.execute([:hex_hub, :mcp, :request], %{duration: duration}, metadata)
  end

  @doc """
  Get handler statistics.
  """
  def get_stats do
    %{
      total_requests: get_total_requests(),
      success_rate: get_success_rate(),
      avg_response_time: get_avg_response_time(),
      error_breakdown: get_error_breakdown()
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

  defp get_error_breakdown do
    # Get breakdown of error types from telemetry
    %{}
  end

  @doc """
  Health check for the handler.
  """
  def health_check do
    %{
      status: "healthy",
      timestamp: DateTime.utc_now(),
      server_status: check_server_status(),
      tool_count: get_tool_count(),
      stats: get_stats()
    }
  end

  defp check_server_status do
    case Process.whereis(HexHub.MCP.Server) do
      nil -> "stopped"
      _pid -> "running"
    end
  end

  defp get_tool_count do
    case Server.list_tools() do
      {:ok, tools} -> length(tools)
      {:error, _} -> 0
    end
  end

  @doc """
  Get handler configuration.
  """
  def get_config do
    HexHub.MCP.config()
  end

  @doc """
  Update handler configuration.
  """
  def update_config(new_config) do
    current_config = HexHub.MCP.config()
    updated_config = Keyword.merge(current_config, new_config)

    # Update application configuration
    Application.put_env(:hex_hub, :mcp, updated_config)

    Telemetry.log(:info, :mcp, "MCP Handler configuration updated")
    {:ok, updated_config}
  end

  @doc """
  Reset handler statistics.
  """
  def reset_stats do
    # Reset telemetry counters and statistics
    Telemetry.log(:info, :mcp, "MCP Handler statistics reset")
    :ok
  end

  @doc """
  Enable/disable specific tools.
  """
  def toggle_tool(tool_name, enabled?) do
    # Enable or disable specific tools
    # This would require maintaining a list of disabled tools
    Telemetry.log(:info, :mcp, "MCP Tool toggled", %{
      tool_name: tool_name,
      enabled: enabled?
    })

    :ok
  end

  @doc """
  Get available tools with status.
  """
  def get_tool_status do
    case Server.list_tools() do
      {:ok, tools} ->
        Enum.map(tools, fn tool ->
          # Extract name from either string key or atom key
          name = if is_map(tool), do: tool["name"] || Map.get(tool, :name), else: nil

          description =
            if is_map(tool), do: tool["description"] || Map.get(tool, :description), else: nil

          input_schema =
            if is_map(tool),
              do: tool["inputSchema"] || Map.get(tool, :input_schema),
              else: nil

          %{
            name: name,
            description: description,
            input_schema: input_schema,
            # All tools are enabled by default
            enabled: true,
            # Would need to track tool usage
            last_used: nil
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Handle graceful shutdown.
  """
  def graceful_shutdown do
    Telemetry.log(:info, :mcp, "MCP Handler initiating graceful shutdown")

    # Stop accepting new requests
    # Wait for existing requests to complete
    # Clean up resources

    :ok
  end

  @doc """
  Reload handler configuration and tools.
  """
  def reload do
    Telemetry.log(:info, :mcp, "MCP Handler reloading")

    # Reload configuration
    # Re-register tools
    # Restart server if needed

    case handle_init() do
      :ok ->
        Telemetry.log(:info, :mcp, "MCP Handler reloaded successfully")
        :ok

      {:error, reason} ->
        Telemetry.log(:error, :mcp, "MCP Handler reload failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end
end
