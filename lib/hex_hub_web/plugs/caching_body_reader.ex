defmodule HexHubWeb.CachingBodyReader do
  @moduledoc """
  A body reader that caches the raw body for later access.

  This is needed for endpoints that need to access the raw body
  after Plug.Parsers has processed it (e.g., hex publish endpoint).
  """

  alias HexHub.Telemetry

  @doc """
  Read the body and cache it in the connection's private storage.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        # Cache the raw body
        Telemetry.log(:debug, :api, "CachingBodyReader: read body (complete)", %{
          bytes: byte_size(body)
        })

        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        # For chunked bodies, accumulate
        existing = conn.private[:raw_body] || ""

        Telemetry.log(:debug, :api, "CachingBodyReader: read body (more)", %{
          bytes: byte_size(body)
        })

        conn = Plug.Conn.put_private(conn, :raw_body, existing <> body)
        {:more, body, conn}

      {:error, reason} ->
        Telemetry.log(:debug, :api, "CachingBodyReader: error reading body", %{
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Get the cached raw body from the connection.
  """
  def get_raw_body(conn) do
    body = conn.private[:raw_body]

    if body do
      Telemetry.log(:debug, :api, "CachingBodyReader: returning cached body", %{
        bytes: byte_size(body)
      })
    else
      Telemetry.log(:debug, :api, "CachingBodyReader: no cached body found", %{})
    end

    body
  end
end
