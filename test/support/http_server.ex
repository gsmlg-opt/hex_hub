defmodule HexHub.TestHTTPServer do
  @moduledoc false

  def child_spec(handler) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler]}
    }
  end

  def start_link(handler) do
    Gaoxy.HTTP.start_link(
      id: :http,
      plug: {__MODULE__, handler},
      ip: {127, 0, 0, 1},
      port: 0,
      limits: %{max_bytes: 268_435_456}
    )
  end

  def url(pid) do
    %{local: {:ok, {_address, port}}} = Gaoxy.info(pid, :http)
    "http://127.0.0.1:#{port}"
  end

  def init(handler), do: handler
  def call(conn, handler), do: handler.(conn)
end
