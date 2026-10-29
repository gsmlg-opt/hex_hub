defmodule Mix.Tasks.Test.E2e do
  @shortdoc "Runs E2E tests from e2e_test directory"

  @moduledoc """
  Runs end-to-end tests for HexHub's hex mirror functionality.

  This task runs tests from the `e2e_test/` directory in isolation from
  the regular unit tests in `test/`. E2E tests verify that HexHub can
  successfully proxy packages from hex.pm.

  ## Test Isolation

  E2E tests are completely isolated from unit tests:

    * `mix test` runs only tests from `test/` directory
    * `mix test.e2e` runs only tests from `e2e_test/` directory

  This ensures that E2E tests (which require network access and start
  a real server) don't interfere with fast unit tests.

  ### How Isolation Works

  1. **Compilation**: The `elixirc_paths` in `mix.exs` does NOT include
     `e2e_test/` for any environment. This prevents `mix compile` from
     compiling E2E test modules as part of the regular build.

  2. **Runtime Compilation**: This task manually compiles `e2e_test/support/`
     modules at runtime using `Code.compile_file/1`, keeping them separate
     from the main codebase.

  3. **Test Discovery**: ExUnit is configured to only discover and run
     tests from `e2e_test/` directory, not `test/`.

  ## Usage

      # Run all E2E tests
      mix test.e2e

      # Run with verbose output
      mix test.e2e --trace

      # Run with specific seed
      mix test.e2e --seed 12345

      # Run specific test file
      mix test.e2e e2e_test/proxy_test.exs

  ## Requirements

    * Network access to hex.pm (for upstream package fetching)
    * Available port for dynamic allocation

  ## Exit Codes

    * 0 - All tests passed
    * 1 - Some tests failed
    * 2 - Test execution error
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    # Parse arguments to separate test files from ExUnit options
    {test_files, exunit_args} = parse_args(args)

    # Compile the e2e_test support files
    compile_e2e_support()

    # Configure ExUnit
    configure_exunit(exunit_args)

    # Determine which test files to run
    test_paths = resolve_test_paths(test_files)

    if Enum.empty?(test_paths) do
      Mix.shell().info("No E2E test files found in e2e_test/")
      exit({:shutdown, 0})
    end

    # Load and run the tests
    require_test_files(test_paths)

    # Run ExUnit and get exit code
    case ExUnit.run() do
      %{failures: 0} ->
        exit({:shutdown, 0})

      %{failures: failures} when failures > 0 ->
        exit({:shutdown, 1})

      _ ->
        exit({:shutdown, 2})
    end
  end

  defp parse_args(args) do
    # Separate file paths from ExUnit options
    {files, opts} =
      Enum.split_with(args, fn arg ->
        String.ends_with?(arg, ".exs") or File.dir?(arg)
      end)

    {files, opts}
  end

  defp compile_e2e_support do
    e2e_support_path = Path.join([File.cwd!(), "e2e_test", "support"])

    if File.dir?(e2e_support_path) do
      # Compile support files in dependency order
      # server_helper.ex must come before e2e_case.ex (which depends on it)
      support_files =
        Path.wildcard(Path.join(e2e_support_path, "**/*.ex"))
        |> sort_by_dependency()

      Enum.each(support_files, fn file ->
        Code.compile_file(file)
      end)
    end
  end

  # Sort support files so dependencies come first
  # e2e_case.ex depends on server_helper.ex and publish_helper.ex
  # Dependencies: server_helper.ex < publish_helper.ex < e2e_case.ex
  defp sort_by_dependency(files) do
    # Define priority: lower number = compile first
    priority = fn file ->
      case Path.basename(file) do
        "server_helper.ex" -> 1
        "publish_helper.ex" -> 2
        "e2e_case.ex" -> 10
        _ -> 5
      end
    end

    Enum.sort_by(files, priority)
  end

  defp configure_exunit(args) do
    # Load the test helper
    test_helper = Path.join([File.cwd!(), "e2e_test", "test_helper.exs"])

    if File.exists?(test_helper) do
      Code.require_file(test_helper)
    else
      # Start ExUnit with defaults if no helper
      ExUnit.start()
    end

    # Apply command line options
    apply_exunit_options(args)
  end

  defp apply_exunit_options(args) do
    opts = parse_exunit_opts(args)

    if opts[:trace] do
      ExUnit.configure(trace: true)
    end

    if opts[:seed] do
      ExUnit.configure(seed: opts[:seed])
    end

    if opts[:max_cases] do
      ExUnit.configure(max_cases: opts[:max_cases])
    end

    if opts[:timeout] do
      ExUnit.configure(timeout: opts[:timeout])
    end
  end

  defp parse_exunit_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          trace: :boolean,
          seed: :integer,
          max_cases: :integer,
          timeout: :integer
        ]
      )

    opts
  end

  defp resolve_test_paths([]) do
    # Default: all test files in e2e_test/
    e2e_test_dir = Path.join(File.cwd!(), "e2e_test")

    if File.dir?(e2e_test_dir) do
      Path.wildcard(Path.join(e2e_test_dir, "**/*_test.exs"))
    else
      []
    end
  end

  defp resolve_test_paths(files) do
    # Use specified files/directories
    Enum.flat_map(files, fn path ->
      cond do
        File.dir?(path) ->
          Path.wildcard(Path.join(path, "**/*_test.exs"))

        File.exists?(path) ->
          [path]

        true ->
          Mix.shell().error("Test file not found: #{path}")
          []
      end
    end)
  end

  defp require_test_files(paths) do
    Enum.each(paths, fn path ->
      Code.require_file(path)
    end)
  end
end
