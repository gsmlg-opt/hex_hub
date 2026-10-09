defmodule E2E.ProxyTest do
  @moduledoc """
  E2E tests for HexHub's hex package proxy functionality.

  These tests verify that HexHub can successfully proxy package requests
  from hex.pm, allowing clients to use HexHub as a transparent hex mirror.
  """

  use E2E.Case

  # Default timeout for E2E test scenarios (120 seconds)
  # Proxy tests may take longer due to network latency to hex.pm
  @test_timeout 120_000

  # Path to test fixture project
  @fixture_project_path Path.join([File.cwd!(), "e2e_test", "fixtures", "test_project"])

  setup_all context do
    # Cleanup fixture project before tests
    cleanup_fixture_project()

    # Setup hex mirror environment
    E2E.ServerHelper.setup_hex_mirror_env(context.port)

    on_exit(fn ->
      # Cleanup after all tests
      cleanup_fixture_project()
      E2E.ServerHelper.clear_hex_mirror_env()
    end)

    :ok
  end

  describe "package proxy functionality" do
    @tag timeout: @test_timeout
    test "fetches jason package through HexHub proxy", %{port: port, base_url: _base_url} do
      # Ensure fixture project is clean
      cleanup_fixture_project()

      # Get environment variables for hex mirror
      env = E2E.ServerHelper.hex_mirror_env(port)

      # Run mix deps.get in the fixture project
      {output, exit_code} =
        System.cmd(
          "mix",
          ["deps.get"],
          cd: @fixture_project_path,
          env: env,
          stderr_to_stdout: true
        )

      # Assert success
      assert exit_code == 0,
             """
             Failed to fetch dependencies through HexHub proxy.

             Exit code: #{exit_code}
             Output: #{output}

             This may indicate:
             - HexHub server failed to start on port #{port}
             - Network connectivity issues to hex.pm
             - Package registry configuration problems

             Verify that:
             1. HexHub is running and accessible at http://localhost:#{port}
             2. Network access to https://hex.pm is available
             3. The fixture project at #{@fixture_project_path} has valid mix.exs
             """

      # Verify deps directory was created
      deps_path = Path.join(@fixture_project_path, "deps")

      assert File.dir?(deps_path),
             """
             Dependencies directory was not created.

             Expected: #{deps_path} to exist
             Output: #{output}
             """

      # Verify jason package was fetched
      jason_path = Path.join(deps_path, "jason")

      assert File.dir?(jason_path),
             """
             Jason package was not fetched through proxy.

             Expected: #{jason_path} to exist
             Dependencies present: #{inspect(File.ls!(deps_path))}
             Output: #{output}

             This may indicate the proxy is not correctly forwarding package requests.
             """

      # Verify mix.lock was created
      lock_path = Path.join(@fixture_project_path, "mix.lock")

      assert File.exists?(lock_path),
             """
             mix.lock was not created.

             Expected: #{lock_path} to exist
             Output: #{output}
             """
    end

    @tag timeout: @test_timeout
    test "server responds to health check", %{base_url: base_url} do
      # Verify the server is running and healthy
      case HexHub.HTTPClient.get("#{base_url}/health") do
        {:ok, %{status: status}} when status in [200, 204] ->
          assert true

        {:ok, %{status: status, body: body}} ->
          flunk("""
          Health check returned unexpected status.

          Status: #{status}
          Body: #{inspect(body)}
          URL: #{base_url}/health
          """)

        {:error, reason} ->
          flunk("""
          Failed to connect to HexHub server for health check.

          URL: #{base_url}/health
          Error: #{inspect(reason)}

          Verify the server started correctly on the expected port.
          """)
      end
    end

    @tag timeout: @test_timeout
    test "proxy returns package metadata", %{base_url: base_url} do
      # Fetch package metadata through the proxy
      case HexHub.HTTPClient.get("#{base_url}/api/packages/jason", json: true) do
        {:ok, %{status: 200, body: body}} ->
          assert is_map(body) or is_binary(body),
                 "Package metadata should be returned"

        {:ok, %{status: status}} ->
          flunk("""
          Failed to fetch package metadata.

          Status: #{status}
          URL: #{base_url}/api/packages/jason

          Expected status 200 for package metadata request.
          """)

        {:error, reason} ->
          flunk("""
          Failed to connect to HexHub for package metadata.

          URL: #{base_url}/api/packages/jason
          Error: #{inspect(reason)}
          """)
      end
    end
  end

  describe "error handling" do
    @tag timeout: @test_timeout
    test "returns 404 for non-existent package", %{base_url: base_url} do
      # Request a package that doesn't exist
      case HexHub.HTTPClient.get(
             "#{base_url}/api/packages/this_package_definitely_does_not_exist_12345"
           ) do
        {:ok, %{status: 404}} ->
          assert true

        {:ok, %{status: status}} ->
          # Some proxies may return different status codes
          assert status in [404, 400],
                 "Expected 404 or 400 for non-existent package, got #{status}"

        {:error, reason} ->
          flunk("""
          Failed to connect to HexHub.

          Error: #{inspect(reason)}
          """)
      end
    end
  end
end
