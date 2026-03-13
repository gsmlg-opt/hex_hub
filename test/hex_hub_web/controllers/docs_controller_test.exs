defmodule HexHubWeb.DocsControllerTest do
  use HexHubWeb.ConnCase

  describe "GET /docs" do
    test "renders documentation index page", %{conn: conn} do
      conn = get(conn, ~p"/docs")

      assert html_response(conn, 200) =~ "Documentation"
      assert html_response(conn, 200) =~ "HexHub Docs"
    end

    test "contains navigation links", %{conn: conn} do
      conn = get(conn, ~p"/docs")

      assert html_response(conn, 200) =~ "Getting Started"
      assert html_response(conn, 200) =~ "Publishing"
      assert html_response(conn, 200) =~ "API Reference"
    end
  end

  describe "GET /docs/getting-started" do
    test "renders getting started page", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")

      assert html_response(conn, 200) =~ "Getting Started"
    end

    test "contains HEX_MIRROR configuration", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")

      assert html_response(conn, 200) =~ "HEX_MIRROR"
    end

    test "contains code snippets", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")

      # Should have code blocks with configuration examples
      assert html_response(conn, 200) =~ "font-mono"
    end
  end

  describe "GET /docs/publishing" do
    test "renders publishing page", %{conn: conn} do
      conn = get(conn, ~p"/docs/publishing")

      assert html_response(conn, 200) =~ "Publishing"
    end

    test "contains HEX_API_URL configuration", %{conn: conn} do
      conn = get(conn, ~p"/docs/publishing")

      assert html_response(conn, 200) =~ "HEX_API_URL"
    end

    test "contains API key documentation", %{conn: conn} do
      conn = get(conn, ~p"/docs/publishing")

      assert html_response(conn, 200) =~ "HEX_API_KEY"
    end
  end

  describe "GET /docs/api-reference" do
    test "renders API reference page", %{conn: conn} do
      conn = get(conn, ~p"/docs/api-reference")

      assert html_response(conn, 200) =~ "API Reference"
    end

    test "contains API endpoints grouped by category", %{conn: conn} do
      conn = get(conn, ~p"/docs/api-reference")

      # Should have categories from the OpenAPI spec
      assert html_response(conn, 200) =~ "Users"
      assert html_response(conn, 200) =~ "Packages"
    end

    test "displays endpoint methods with badges", %{conn: conn} do
      conn = get(conn, ~p"/docs/api-reference")

      # Should show HTTP methods
      assert html_response(conn, 200) =~ "GET"
      assert html_response(conn, 200) =~ "POST"
    end
  end

  describe "OpenAPI static file" do
    test "OpenAPI YAML file is accessible", %{conn: conn} do
      conn = get(conn, "/openapi/hex-api.yaml")

      assert response(conn, 200)
      # Content-type may vary (application/yaml, text/yaml, or octet-stream)
      # The important thing is the file is served successfully
      assert get_resp_header(conn, "content-type") != []
    end
  end
end
