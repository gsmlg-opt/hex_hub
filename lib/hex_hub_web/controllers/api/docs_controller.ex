defmodule HexHubWeb.API.DocsController do
  use HexHubWeb, :controller

  alias HexHub.Packages

  action_fallback HexHubWeb.FallbackController

  def publish(conn, %{"name" => name, "version" => version}) do
    with {:ok, body} <- extract_body(conn),
         {:ok, release} <- Packages.upload_docs(name, version, body) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", release.docs_html_url)
      |> send_resp(201, "")
    else
      {:error, "Package not found"} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})

      {:error, "Release not found"} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Release not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: reason})
    end
  end

  # Extract body from conn, preferring the pre-parsed raw_body from TarballParser
  defp extract_body(conn) do
    case conn.private[:raw_body] do
      body when is_binary(body) and byte_size(body) > 0 ->
        {:ok, body}

      _ ->
        case Plug.Conn.read_body(conn,
               length: 100_000_000,
               read_length: 1_000_000,
               read_timeout: 120_000
             ) do
          {:ok, body, _conn} -> {:ok, body}
          {:more, _partial, _conn} -> {:error, "Body too large"}
          {:error, reason} -> {:error, "Failed to read body: #{inspect(reason)}"}
        end
    end
  end

  def delete(conn, %{"name" => name, "version" => version}) do
    case Packages.delete_docs(name, version) do
      {:ok, _release} ->
        send_resp(conn, 204, "")

      {:error, "Package not found"} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})

      {:error, "Release not found"} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Release not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: reason})
    end
  end
end
