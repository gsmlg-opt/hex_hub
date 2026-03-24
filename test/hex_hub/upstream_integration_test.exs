defmodule HexHub.UpstreamIntegrationTest do
  use ExUnit.Case, async: false

  alias HexHub.Upstream

  # These are integration tests that test the actual upstream functionality
  # They can be run manually to verify real upstream integration

  @moduletag :integration
  @moduletag :external

  describe "real upstream integration" do
    # Integration tests - run with HEX_HUB_INTEGRATION_TESTS=true

    test "fetch package metadata from real hex.pm" do
      if System.get_env("HEX_HUB_INTEGRATION_TESTS") != "true" do
        :ok
      else
        # This test actually hits hex.pm - run with HEX_HUB_INTEGRATION_TESTS=true
        Application.put_env(:hex_hub, :upstream,
          enabled: true,
          api_url: "https://hex.pm",
          repo_url: "https://repo.hex.pm",
          timeout: 10_000,
          retry_attempts: 2,
          retry_delay: 500
        )

        # Test with a well-known package
        package_name = "phoenix"

        case Upstream.fetch_package(package_name) do
          {:ok, package_data} ->
            assert package_data["name"] == package_name
            assert is_map(package_data["meta"])
            assert is_binary(package_data["repository"])

          {:error, reason} ->
            flunk("Failed to fetch package: #{reason}")
        end
      end
    end

    test "fetch releases from real hex.pm" do
      if System.get_env("HEX_HUB_INTEGRATION_TESTS") != "true" do
        :ok
      else
        Application.put_env(:hex_hub, :upstream,
          enabled: true,
          api_url: "https://hex.pm",
          repo_url: "https://repo.hex.pm",
          timeout: 10_000,
          retry_attempts: 2,
          retry_delay: 500
        )

        package_name = "phoenix"

        case Upstream.fetch_releases(package_name) do
          {:ok, releases} when is_list(releases) ->
            assert releases != []
            first_release = hd(releases)
            assert is_map(first_release)
            assert is_binary(first_release["version"])

          {:error, reason} ->
            flunk("Failed to fetch releases: #{reason}")
        end
      end
    end

    test "fetch non-existent package returns error" do
      if System.get_env("HEX_HUB_INTEGRATION_TESTS") != "true" do
        :ok
      else
        Application.put_env(:hex_hub, :upstream,
          enabled: true,
          api_url: "https://hex.pm",
          repo_url: "https://repo.hex.pm",
          timeout: 10_000,
          retry_attempts: 1,
          retry_delay: 100
        )

        package_name = "definitelydoesnotexist12345package"

        assert {:error, "Package not found upstream"} = Upstream.fetch_package(package_name)
      end
    end
  end

  describe "upstream fallback integration" do
    test "basic upstream configuration check" do
      # Configure upstream to be enabled via the UpstreamConfig module (not Application.put_env)
      # The Upstream module reads from Mnesia, not Application config
      :ok =
        HexHub.UpstreamConfig.update_config(%{
          enabled: true,
          api_url: "https://hex.pm",
          repo_url: "https://repo.hex.pm",
          timeout: 30_000,
          retry_attempts: 1,
          retry_delay: 100
        })

      # Test that upstream is enabled
      assert HexHub.Upstream.enabled?() == true

      # Test that we can get configuration
      config = HexHub.Upstream.config()
      assert config.enabled == true
      assert config.api_url == "https://hex.pm"
      assert config.repo_url == "https://repo.hex.pm"
    end
  end
end
