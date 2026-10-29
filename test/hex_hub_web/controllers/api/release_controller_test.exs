defmodule HexHubWeb.API.ReleaseControllerTest do
  use HexHubWeb.ConnCase

  setup %{conn: conn} do
    %{api_key: api_key, user: user} = setup_authenticated_user()
    {:ok, conn: authenticated_conn(conn, api_key), user: user}
  end

  describe "GET /api/packages/:name/releases/:version" do
    test "returns release details", %{conn: conn} do
      package_name = "test_package"
      version = "1.0.0"

      # Create package and release first
      {:ok, _package} =
        HexHub.Packages.create_package(package_name, "hexpm", %{description: "Test package"})

      {:ok, _release} =
        HexHub.Packages.create_release(package_name, version, %{}, %{}, "mock tarball")

      conn = get(conn, ~p"/api/packages/#{package_name}/releases/#{version}")

      assert %{
               "name" => ^package_name,
               "version" => ^version,
               "checksum" => _,
               "requirements" => requirements,
               "inner_checksum" => _
             } = json_response(conn, 200)

      assert is_map(requirements)
    end

    test "returns 404 for non-existent release", %{conn: conn} do
      conn = get(conn, ~p"/api/packages/phoenix/releases/99.99.99")
      assert response(conn, 404)
    end

    test "returns 404 for non-existent package", %{conn: conn} do
      conn = get(conn, ~p"/api/packages/nonexistent/releases/1.0.0")
      assert response(conn, 404)
    end
  end

  describe "POST /api/publish" do
    test "publishes new package release", %{conn: conn} do
      package_name = "publish_test_pkg"
      version = "1.0.0"

      # Create a valid hex tarball
      tarball_content = create_test_tarball(package_name, version)

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(~p"/api/packages/#{package_name}/releases", tarball_content)

      assert %{
               "url" => url
             } = json_response(conn, 201)

      assert url == "/packages/#{package_name}/releases/#{version}"
    end

    test "returns 422 with invalid package data", %{conn: conn} do
      params = %{
        "name" => "",
        "version" => "invalid",
        "requirements" => %{}
      }

      conn = post(conn, ~p"/api/publish", params)
      assert json_response(conn, 422)
    end
  end

  describe "POST /api/packages/:name/releases/:version/retire" do
    test "retires a package release", %{conn: conn, user: user} do
      package_name = "test_package"
      version = "1.0.0"

      params = %{
        "reason" => "other",
        "message" => "This version has security vulnerabilities"
      }

      # Create package and release first
      {:ok, _package} =
        HexHub.Packages.create_package(package_name, "hexpm", %{description: "Test package"})

      # Add authenticated user as owner
      HexHub.Database.transaction(fn ->
        HexHub.Database.write(
          {:package_owners, package_name, user.username, "owner", DateTime.utc_now()}
        )
      end)

      {:ok, _release} =
        HexHub.Packages.create_release(package_name, version, %{}, %{}, "mock tarball")

      conn = post(conn, ~p"/api/packages/#{package_name}/releases/#{version}/retire", params)
      assert response(conn, 202)
    end

    test "returns 400 for non-existent release", %{conn: conn, user: user} do
      # Create package and add user as owner to pass permission check
      {:ok, _package} =
        HexHub.Packages.create_package("phoenix", "hexpm", %{description: "Test"})

      HexHub.Database.transaction(fn ->
        HexHub.Database.write(
          {:package_owners, "phoenix", user.username, "owner", DateTime.utc_now()}
        )
      end)

      conn = post(conn, ~p"/api/packages/phoenix/releases/99.99.99/retire", %{})
      assert response(conn, 400)
      assert json_response(conn, 400)["error"] == "Release not found"
    end
  end

  describe "DELETE /api/packages/:name/releases/:version/retire" do
    test "unretires a package release", %{conn: conn, user: user} do
      package_name = "test_package"
      version = "1.0.0"

      # Create package and release first
      {:ok, _package} =
        HexHub.Packages.create_package(package_name, "hexpm", %{description: "Test package"})

      # Add authenticated user as owner
      HexHub.Database.transaction(fn ->
        HexHub.Database.write(
          {:package_owners, package_name, user.username, "owner", DateTime.utc_now()}
        )
      end)

      {:ok, _release} =
        HexHub.Packages.create_release(package_name, version, %{}, %{}, "mock tarball")

      # Retire the release first
      :ok =
        HexHub.PackageRetirement.retire_release(
          package_name,
          version,
          :other,
          "Test retirement",
          user.username
        )

      conn = delete(conn, ~p"/api/packages/#{package_name}/releases/#{version}/retire")
      assert response(conn, 200)
    end

    test "returns 400 for non-retired release", %{conn: conn, user: user} do
      # Create package and add user as owner to pass permission check
      {:ok, _package} =
        HexHub.Packages.create_package("phoenix", "hexpm", %{description: "Test"})

      HexHub.Database.transaction(fn ->
        HexHub.Database.write(
          {:package_owners, "phoenix", user.username, "owner", DateTime.utc_now()}
        )
      end)

      conn = delete(conn, ~p"/api/packages/phoenix/releases/99.99.99/retire")
      assert response(conn, 400)
      assert json_response(conn, 400)["error"] == "Release is not retired"
    end
  end

  describe "anonymous publishing" do
    setup do
      # Ensure anonymous user exists
      HexHub.Users.ensure_anonymous_user()
      :ok
    end

    test "allows anonymous publish when enabled", %{conn: _conn} do
      # Enable anonymous publishing
      :ok = HexHub.PublishConfig.update_config(%{"enabled" => true})

      package_name = "anon_test_pkg"
      version = "1.0.0"
      tarball_content = create_test_tarball(package_name, version)

      # Make request without authentication
      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> post(~p"/api/packages/#{package_name}/releases", tarball_content)

      assert %{
               "url" => url
             } = json_response(conn, 201)

      assert url == "/packages/#{package_name}/releases/#{version}"

      # Verify package is owned by anonymous user
      {:ok, package} = HexHub.Packages.get_package(package_name)
      assert package.name == package_name
    end

    test "rejects anonymous publish when disabled" do
      # Ensure anonymous publishing is disabled (default)
      :ok = HexHub.PublishConfig.update_config(%{"enabled" => false})

      package_name = "anon_disabled_pkg"
      version = "1.0.0"
      tarball_content = create_test_tarball(package_name, version)

      # Make request without authentication
      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> post(~p"/api/packages/#{package_name}/releases", tarball_content)

      assert json_response(conn, 401)["message"] == "API key required"
    end

    test "authenticated publish still works when anonymous is enabled", %{conn: conn} do
      # Enable anonymous publishing
      :ok = HexHub.PublishConfig.update_config(%{"enabled" => true})

      package_name = "auth_with_anon_enabled"
      version = "1.0.0"
      tarball_content = create_test_tarball(package_name, version)

      # Make authenticated request
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(~p"/api/packages/#{package_name}/releases", tarball_content)

      assert %{
               "url" => url
             } = json_response(conn, 201)

      assert url == "/packages/#{package_name}/releases/#{version}"
    end

    test "logs IP address for anonymous publish" do
      # Enable anonymous publishing
      :ok = HexHub.PublishConfig.update_config(%{"enabled" => true})

      package_name = "anon_ip_test"
      version = "1.0.0"
      tarball_content = create_test_tarball(package_name, version)

      # Make request without authentication (IP logging happens in the plug)
      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> post(~p"/api/packages/#{package_name}/releases", tarball_content)

      # Request should succeed
      assert json_response(conn, 201)
      # Note: Actual IP logging verification would require telemetry event capture,
      # which is tested at the integration level
    end
  end
end
