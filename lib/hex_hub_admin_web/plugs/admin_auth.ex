defmodule HexHubAdminWeb.Plugs.AdminAuth do
  @moduledoc """
  Basic authentication plug for admin dashboard.

  Configure admin credentials via environment variables:
    - ADMIN_USERNAME (default: "admin")
    - ADMIN_PASSWORD (required in production, default: "admin" in dev)

  ## Security Notes

  - In production, always set ADMIN_PASSWORD to a strong password
  - Consider using a reverse proxy with additional auth in production
  - Sessions are stored server-side for security
  """

  import Plug.Conn
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if admin_authenticated?(conn) do
      conn
    else
      authenticate_admin(conn)
    end
  end

  defp admin_authenticated?(conn) do
    get_session(conn, :admin_authenticated) == true
  end

  defp authenticate_admin(conn) do
    with {user, pass} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- valid_credentials?(user, pass) do
      conn
      |> put_session(:admin_authenticated, true)
      |> put_session(:admin_username, user)
    else
      _ ->
        conn
        |> Plug.BasicAuth.request_basic_auth(realm: "HexHub Admin")
        |> halt()
    end
  end

  defp valid_credentials?(username, password) do
    expected_username = get_admin_username()
    expected_password = get_admin_password()

    # Constant-time comparison to prevent timing attacks
    Plug.Crypto.secure_compare(username, expected_username) and
      Plug.Crypto.secure_compare(password, expected_password)
  end

  defp get_admin_username do
    Application.get_env(:hex_hub, :admin_username, "admin")
  end

  defp get_admin_password do
    case Application.get_env(:hex_hub, :admin_password) do
      nil ->
        if Application.get_env(:hex_hub, :env) == :prod do
          raise "ADMIN_PASSWORD must be set in production!"
        else
          # Default for development only
          "admin"
        end

      password ->
        password
    end
  end

  @doc """
  Check if admin password is configured (for health checks).
  """
  @spec password_configured?() :: boolean()
  def password_configured? do
    Application.get_env(:hex_hub, :admin_password) != nil
  end

  @doc """
  Logout admin session.
  """
  @spec logout(Plug.Conn.t()) :: Plug.Conn.t()
  def logout(conn) do
    conn
    |> delete_session(:admin_authenticated)
    |> delete_session(:admin_username)
  end
end
