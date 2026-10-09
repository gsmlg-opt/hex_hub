defmodule HexHub.TestHTTPServer do
  @moduledoc false

  def child_spec(handler) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler]}
    }
  end

  def start_link(handler) do
    Bandit.start_link(
      plug: {__MODULE__, handler},
      ip: {127, 0, 0, 1},
      port: 0,
      startup_log: false
    )
  end

  def url(pid) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  def init(handler), do: handler
  def call(conn, handler), do: handler.(conn)
end
