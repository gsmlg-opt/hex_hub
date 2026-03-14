defmodule HexHubAdminWeb.TokenController do
  use HexHubAdminWeb, :controller

  alias HexHub.ApiKeys

  def index(conn, _params) do
    {:ok, tokens} = ApiKeys.list_all_keys()

    render(conn, :index, tokens: tokens)
  end

  def create(conn, %{"username" => username, "token" => token_params}) do
    name = token_params["name"]
    permissions = parse_permissions(token_params)

    case ApiKeys.generate_key(name, username, permissions) do
      {:ok, _key} ->
        conn
        |> put_flash(:info, "Token created successfully.")
        |> redirect(to: ~p"/users/#{username}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create token: #{reason}")
        |> redirect(to: ~p"/users/#{username}")
    end
  end

  def revoke(conn, %{"username" => username, "name" => name}) do
    case ApiKeys.revoke_key(name, username) do
      :ok ->
        conn
        |> put_flash(:info, "Token \"#{name}\" revoked successfully.")
        |> redirect(to: ~p"/users/#{username}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to revoke token: #{reason}")
        |> redirect(to: ~p"/users/#{username}")
    end
  end

  defp parse_permissions(params) do
    permissions = []
    permissions = if params["perm_read"] == "true", do: ["read" | permissions], else: permissions
    permissions = if params["perm_write"] == "true", do: ["write" | permissions], else: permissions
    if permissions == [], do: ["read"], else: permissions
  end
end
