defmodule HexHubWeb.BadgeControllerTest do
  use HexHubWeb.ConnCase

  alias HexHub.Packages

  setup %{conn: conn} do
    Packages.reset_test_store()
    {:ok, conn: conn}
  end

  describe "GET /packages/:name/badge.svg" do
    test "returns SVG badge with latest version", %{conn: conn} do
      {:ok, _} =
        Packages.create_package("phoenix", "hexpm", %{
          "description" => "Web framework"
        })

      {:ok, _} = Packages.create_release("phoenix", "1.7.0", %{}, %{}, "tarball")
      {:ok, _} = Packages.create_release("phoenix", "1.8.1", %{}, %{}, "tarball")

      conn = get(conn, "/packages/phoenix/badge.svg")

      assert response_content_type(conn, :xml) =~ "image/svg+xml"
      body = response(conn, 200)
      assert body =~ "phoenix"
      assert body =~ "1.8.1" or body =~ "1.7.0"
      assert body =~ "<svg"
    end

    test "returns 'not found' badge for missing package", %{conn: conn} do
      conn = get(conn, "/packages/nonexistent/badge.svg")

      body = response(conn, 200)
      assert body =~ "not found"
      assert body =~ "<svg"
    end

    test "returns 'no releases' badge for package without releases", %{conn: conn} do
      {:ok, _} =
        Packages.create_package("empty_pkg", "hexpm", %{
          "description" => "No releases yet"
        })

      conn = get(conn, "/packages/empty_pkg/badge.svg")

      body = response(conn, 200)
      assert body =~ "no releases"
      assert body =~ "<svg"
    end

    test "sets cache-control header", %{conn: conn} do
      {:ok, _} =
        Packages.create_package("cached_pkg", "hexpm", %{
          "description" => "Test"
        })

      conn = get(conn, "/packages/cached_pkg/badge.svg")

      assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
    end
  end
end
