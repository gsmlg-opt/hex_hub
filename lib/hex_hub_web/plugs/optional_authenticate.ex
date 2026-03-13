defmodule HexHubWeb.Plugs.OptionalAuthenticate do
  @moduledoc """
  Optional authentication plug for API endpoints that support anonymous access.

  When anonymous publishing is enabled (via `HexHub.PublishConfig`), this plug allows
  requests without authentication by assigning the "anonymous" system user.

  When anonymous publishing is disabled, this plug requires authentication just like
  the standard `Authenticate` plug.

  IP addresses are logged via telemetry for anonymous requests.
  """

  import Plug.Conn
  alias HexHub.ApiKeys
  alias HexHub.PublishConfig
  alias HexHub.Telemetry
  alias HexHub.Users
  alias Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_api_key(conn) do
      {:ok, key} ->
        # API key provided - validate it normally
        validate_api_key(conn, key)

      {:error, :missing_key} ->
        # No API key - check if anonymous publishing is enabled
        handle_missing_key(conn)

      {:error, :invalid_format} ->
        conn
        |> put_status(401)
        |> Controller.json(%{"message" => "Invalid authorization format", "status" => 401})
        |> halt()
    end
  end

  defp validate_api_key(conn, key) do
    case ApiKeys.validate_key(key) do
      {:ok, %{username: username, permissions: permissions}} ->
        assign(conn, :current_user, %{username: username, permissions: permissions})

      {:error, :invalid_key} ->
        # If anonymous publishing is enabled, fall back to anonymous user
        # instead of rejecting. This allows clients to set HEX_API_KEY to
        # any placeholder value (e.g. "anonymous") when no real key exists.
        if PublishConfig.anonymous_publishing_enabled?() do
          assign_anonymous_user(conn)
        else
          conn
          |> put_status(401)
          |> Controller.json(%{"message" => "Invalid API key", "status" => 401})
          |> halt()
        end

      {:error, :revoked_key} ->
        conn
        |> put_status(401)
        |> Controller.json(%{"message" => "API key has been revoked", "status" => 401})
        |> halt()
    end
  end

  defp handle_missing_key(conn) do
    if PublishConfig.anonymous_publishing_enabled?() do
      # Anonymous publishing is enabled - assign anonymous user
      assign_anonymous_user(conn)
    else
      # Anonymous publishing is disabled - require authentication
      conn
      |> put_status(401)
      |> Controller.json(%{"message" => "API key required", "status" => 401})
      |> halt()
    end
  end

  defp assign_anonymous_user(conn) do
    # Get the anonymous user (created at startup)
    case Users.get_user("anonymous") do
      {:ok, _user} ->
        # Log anonymous publish attempt with IP
        ip_address = get_client_ip(conn)

        Telemetry.log(:info, :auth, "Anonymous publish request", %{
          ip_address: ip_address,
          path: conn.request_path
        })

        # Assign anonymous user with write permissions for publishing
        assign(conn, :current_user, %{
          username: "anonymous",
          permissions: ["read", "write"],
          is_anonymous: true,
          ip_address: ip_address
        })

      {:error, _} ->
        # Anonymous user doesn't exist (shouldn't happen, but handle gracefully)
        conn
        |> put_status(500)
        |> Controller.json(%{
          "message" => "Anonymous publishing is enabled but anonymous user is missing",
          "status" => 500
        })
        |> halt()
    end
  end

  defp get_client_ip(conn) do
    # Check for forwarded headers first (common with proxies/load balancers)
    forwarded_for = get_req_header(conn, "x-forwarded-for")
    real_ip = get_req_header(conn, "x-real-ip")

    cond do
      forwarded_for != [] ->
        # X-Forwarded-For can contain multiple IPs; take the first one
        forwarded_for
        |> List.first()
        |> String.split(",")
        |> List.first()
        |> String.trim()

      real_ip != [] ->
        List.first(real_ip)

      true ->
        # Fall back to peer IP
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          {a, b, c, d, e, f, g, h} -> "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}:#{g}:#{h}"
          _ -> "unknown"
        end
    end
  end

  defp extract_api_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        case Base.decode64(encoded) do
          {:ok, decoded} ->
            case String.split(decoded, ":") do
              [_username, key] -> {:ok, key}
              _ -> {:error, :invalid_format}
            end

          :error ->
            {:error, :invalid_format}
        end

      ["Bearer " <> key] ->
        {:ok, String.trim(key)}

      # Hex client sends the API key directly without Bearer prefix
      [key] when is_binary(key) and byte_size(key) > 0 ->
        {:ok, String.trim(key)}

      _ ->
        {:error, :missing_key}
    end
  end
end
