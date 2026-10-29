defmodule HexHubWeb.ClusterController do
  use HexHubWeb, :controller

  alias HexHub.Clustering

  def status(conn, _params) do
    status = Clustering.get_cluster_status()
    json(conn, status)
  end

  def join(conn, %{"node" => node}) do
    case Clustering.join_cluster(node) do
      {:ok, _} ->
        json(conn, %{status: "success", message: "Successfully joined cluster"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Failed to join cluster: #{reason}"})
    end
  end

  def leave(conn, _params) do
    case Clustering.leave_cluster() do
      {:ok, _} ->
        json(conn, %{status: "success", message: "Successfully left cluster"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Failed to leave cluster: #{reason}"})
    end
  end
end
