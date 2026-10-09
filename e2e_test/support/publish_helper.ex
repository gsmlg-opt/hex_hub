defmodule E2E.PublishHelper do
  @moduledoc """
  Helper module for hex.publish E2E tests.

  Provides utilities for configuring the hex client environment,
  managing test users and API keys, and cleaning up fixture projects.
  """

  @doc """
  Returns the environment variables needed for hex publish configuration.

  Sets up the hex client to publish to the local HexHub instance.

  ## Parameters

    * `port` - The port the HexHub server is running on
    * `api_key` - The API key for authentication

  ## Example

      env = E2E.PublishHelper.hex_publish_env(4000, "my_api_key")
      System.cmd("mix", ["hex.publish", "--yes"], env: env, cd: project_path)
  """
  @spec hex_publish_env(pos_integer(), String.t()) :: [{String.t(), String.t()}]
  def hex_publish_env(port, api_key) do
    [
      {"HEX_API_URL", "http://localhost:#{port}/api"},
      {"HEX_API_KEY", api_key},
      {"HEX_UNSAFE_REGISTRY", "1"},
      {"HEX_INTERACTIVE", "0"},
      {"MIX_ENV", "dev"}
    ]
  end

  @doc """
  Returns the environment variables for publishing without an API key.

  Used for testing authentication failure scenarios.
  """
  @spec hex_publish_env_no_key(pos_integer()) :: [{String.t(), String.t()}]
  def hex_publish_env_no_key(port) do
    [
      {"HEX_API_URL", "http://localhost:#{port}/api"},
      {"HEX_UNSAFE_REGISTRY", "1"},
      {"HEX_INTERACTIVE", "0"},
      {"MIX_ENV", "dev"}
    ]
  end

  @doc """
  Creates a test user for E2E publish tests.

  ## Parameters

    * `username` - The username (default: "e2e_publisher")
    * `email` - The email (default: "e2e@test.com")
    * `password` - The password (default: "password123456")

  ## Returns

    `{:ok, user}` on success, `{:error, reason}` on failure.
  """
  @spec create_test_user(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def create_test_user(
        username \\ "e2e_publisher",
        email \\ "e2e@test.com",
        password \\ "password123456"
      ) do
    HexHub.Users.create_user(username, email, password)
  end

  @doc """
  Creates an API key with write permissions for the given user.

  ## Parameters

    * `username` - The username to create the key for
    * `key_name` - The name for the API key (default: "e2e_write_key")

  ## Returns

    `{:ok, api_key_secret}` on success, `{:error, reason}` on failure.
  """
  @spec create_write_api_key(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def create_write_api_key(username, key_name \\ "e2e_write_key") do
    HexHub.ApiKeys.generate_key(key_name, username, ["read", "write"])
  end

  @doc """
  Creates an API key with read-only permissions (no write).

  Used for testing permission failure scenarios.

  ## Parameters

    * `username` - The username to create the key for
    * `key_name` - The name for the API key (default: "e2e_read_key")

  ## Returns

    `{:ok, api_key_secret}` on success, `{:error, reason}` on failure.
  """
  @spec create_read_only_api_key(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def create_read_only_api_key(username, key_name \\ "e2e_read_key") do
    HexHub.ApiKeys.generate_key(key_name, username, ["read"])
  end

  @doc """
  Returns the path to the publish fixture project.
  """
  @spec publish_fixture_path() :: String.t()
  def publish_fixture_path do
    Path.join([File.cwd!(), "e2e_test", "fixtures", "publish_project"])
  end

  @doc """
  Returns the path to the invalid publish fixture project.
  Used for testing error handling scenarios.
  """
  @spec invalid_fixture_path() :: String.t()
  def invalid_fixture_path do
    Path.join([File.cwd!(), "e2e_test", "fixtures", "invalid_publish_project"])
  end

  @doc """
  Cleans up the publish fixture project.

  Removes deps/, _build/, mix.lock, and any generated tarballs.
  """
  @spec cleanup_publish_fixture() :: :ok
  def cleanup_publish_fixture do
    project_path = publish_fixture_path()
    File.rm_rf!(Path.join(project_path, "deps"))
    File.rm_rf!(Path.join(project_path, "_build"))
    File.rm_rf!(Path.join(project_path, "doc"))
    File.rm(Path.join(project_path, "mix.lock"))

    # Remove any generated tarballs
    project_path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".tar"))
    |> Enum.each(fn file ->
      File.rm!(Path.join(project_path, file))
    end)

    :ok
  end

  @doc """
  Resets all test data (packages, users, API keys).

  Call this at the start of tests to ensure clean state.
  """
  @spec reset_test_data() :: :ok
  def reset_test_data do
    HexHub.Packages.reset_test_store()
    HexHub.Users.reset_test_store()
    HexHub.ApiKeys.reset_test_store()
    :ok
  end

  @doc """
  Updates the version in the fixture project's mix.exs.

  Modifies the @version module attribute to the specified version.

  ## Parameters

    * `version` - The new version string (e.g., "0.2.0")

  ## Returns

    `:ok` on success.
  """
  @spec update_fixture_version(String.t()) :: :ok
  def update_fixture_version(version) do
    mix_exs_path = Path.join(publish_fixture_path(), "mix.exs")
    content = File.read!(mix_exs_path)

    # Replace the @version module attribute
    updated_content =
      Regex.replace(~r/@version "[\d\.]+"/, content, "@version \"#{version}\"")

    File.write!(mix_exs_path, updated_content)
    :ok
  end

  @doc """
  Runs mix hex.publish package in the fixture project with the given environment.

  Note: Uses `mix hex.publish package --yes` by default to skip docs publishing.

  ## Parameters

    * `env` - Environment variables for the hex client
    * `opts` - Additional options:
      * `:args` - Additional arguments to pass (default: ["package", "--yes"])
      * `:fixture` - Which fixture to use (:valid or :invalid, default: :valid)

  ## Returns

    `{output, exit_code}` tuple from System.cmd/3.
  """
  @spec run_hex_publish([{String.t(), String.t()}], keyword()) :: {String.t(), non_neg_integer()}
  def run_hex_publish(env, opts \\ []) do
    args = Keyword.get(opts, :args, ["package", "--yes"])
    fixture = Keyword.get(opts, :fixture, :valid)
    # 60 second timeout for hex.publish commands
    timeout = Keyword.get(opts, :timeout, 60_000)

    project_path =
      case fixture do
        :invalid -> invalid_fixture_path()
        _ -> publish_fixture_path()
      end

    # Merge our environment variables with the current system environment
    # System.cmd with env: option completely replaces the environment,
    # so we need to preserve PATH, HOME, and other essential variables
    full_env = Map.merge(System.get_env(), Map.new(env)) |> Enum.to_list()

    # Use Task to enforce timeout since System.cmd doesn't support it directly
    task =
      Task.async(fn ->
        System.cmd(
          "mix",
          ["hex.publish" | args],
          cd: project_path,
          env: full_env,
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        # Task timed out, return error
        {"Command timed out after #{timeout}ms", 124}
    end
  end

  @doc """
  Cleans up the invalid publish fixture project.

  Removes deps/, _build/, mix.lock, and any generated tarballs.
  """
  @spec cleanup_invalid_fixture() :: :ok
  def cleanup_invalid_fixture do
    project_path = invalid_fixture_path()
    File.rm_rf!(Path.join(project_path, "deps"))
    File.rm_rf!(Path.join(project_path, "_build"))
    File.rm_rf!(Path.join(project_path, "doc"))
    File.rm(Path.join(project_path, "mix.lock"))

    # Remove any generated tarballs
    case File.ls(project_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".tar"))
        |> Enum.each(fn file ->
          File.rm!(Path.join(project_path, file))
        end)

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Runs mix hex.publish with docs in the fixture project.

  This publishes both the package and documentation together.

  ## Parameters

    * `env` - Environment variables for the hex client

  ## Returns

    `{output, exit_code}` tuple from System.cmd/3.
  """
  @spec run_hex_publish_with_docs([{String.t(), String.t()}]) :: {String.t(), non_neg_integer()}
  def run_hex_publish_with_docs(env) do
    run_hex_publish(env, args: ["--yes"])
  end

  @doc """
  Downloads a documentation tarball via the API.

  ## Parameters

    * `base_url` - The base URL of the HexHub server
    * `package_name` - The name of the package
    * `version` - The version to download

  ## Returns

    `{:ok, binary}` if successful, `{:error, status_code}` otherwise.
  """
  @spec download_docs_tarball(String.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def download_docs_tarball(base_url, package_name, version) do
    url = "#{base_url}/api/packages/#{package_name}/releases/#{version}/docs/download"

    case HexHub.HTTPClient.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies a package exists via the API.

  ## Parameters

    * `base_url` - The base URL of the HexHub server
    * `package_name` - The name of the package to check

  ## Returns

    `{:ok, package_data}` if the package exists, `{:error, status_code}` otherwise.
  """
  @spec verify_package_exists(String.t(), String.t()) ::
          {:ok, map()} | {:error, non_neg_integer()}
  def verify_package_exists(base_url, package_name) do
    url = "#{base_url}/api/packages/#{package_name}"

    case HexHub.HTTPClient.get(url, json: true) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a package tarball via the API.

  ## Parameters

    * `base_url` - The base URL of the HexHub server
    * `package_name` - The name of the package
    * `version` - The version to download

  ## Returns

    `{:ok, binary}` if successful, `{:error, status_code}` otherwise.
  """
  @spec download_package_tarball(String.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def download_package_tarball(base_url, package_name, version) do
    url = "#{base_url}/api/packages/#{package_name}/releases/#{version}/download"

    case HexHub.HTTPClient.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, status}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
