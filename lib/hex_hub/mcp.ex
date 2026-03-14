defmodule HexHub.MCP do
  @moduledoc """
  HexHub MCP (Model Context Protocol) Server Module

  This module provides an optional MCP server that exposes HexHub's package
  management capabilities through JSON-RPC over HTTP/WebSocket transport.

  The MCP server allows AI clients to securely query package information,
  download packages, access documentation, and perform dependency resolution.
  """

  use Application

  def start(_type, _args) do
    unless Application.get_env(:hex_hub, :mcp)[:enabled] do
      :ignore
    else
      children = [
        {Phoenix.PubSub, name: HexHub.MCP.PubSub},
        {HexHub.MCP.DynamicSupervisor, []},
        # Start the MCP log store
        {HexHub.MCP.LogStore, []},
        # Start the MCP server
        %{
          id: HexHub.MCP.Server,
          start: {HexHub.MCP.Server, :start_link, [[]]},
          restart: :transient,
          type: :worker
        }
      ]

      opts = [strategy: :one_for_one, name: HexHub.MCP.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end

  @doc """
  Returns the configuration for the MCP server.
  """
  def config do
    Application.get_env(:hex_hub, :mcp, [])
  end

  @doc """
  Checks if the MCP server is enabled.
  """
  def enabled? do
    config()[:enabled] == true
  end

  @doc """
  Returns the WebSocket path for MCP connections.
  """
  def websocket_path do
    config()[:websocket_path] || "/mcp/ws"
  end

  @doc """
  Returns the rate limit for MCP requests.
  """
  def rate_limit do
    # requests per hour
    config()[:rate_limit] || 1000
  end

  @doc """
  Returns whether authentication is required for MCP connections.
  """
  def require_auth? do
    config()[:require_auth] != false
  end
end
