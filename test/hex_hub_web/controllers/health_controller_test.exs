defmodule HexHubWeb.HealthControllerTest do
  use HexHubWeb.ConnCase, async: false

  alias HexHub.Database

  test "readiness reports the configured metadata backend", %{conn: conn} do
    backend = to_string(Database.backend())
    response = conn |> get("/health/ready") |> json_response(200)

    assert %{"ready" => true, "checks" => checks} = response

    assert %{"name" => ^backend, "status" => "ok", "details" => %{"running" => true}} =
             Enum.find(checks, &(&1["name"] == backend))
  end

  if Database.backend() == :postgresql do
    test "a PostgreSQL outage returns 503 while liveness remains available", %{conn: conn} do
      :ok = Supervisor.terminate_child(HexHub.Database.Supervisor, HexHub.Database.Repo)

      on_exit(fn ->
        {:ok, _pid} =
          Supervisor.restart_child(HexHub.Database.Supervisor, HexHub.Database.Repo)
      end)

      assert %{"ready" => false, "checks" => checks} =
               conn |> get("/health/ready") |> json_response(503)

      assert %{"name" => "postgresql", "status" => "error"} =
               Enum.find(checks, &(&1["name"] == "postgresql"))

      assert %{"alive" => true} = conn |> get("/health/live") |> json_response(200)
      assert %{status: :unhealthy} = HexHub.HealthCheck.ready()
    end
  end
end
