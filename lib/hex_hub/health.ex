defmodule HexHub.HealthCheck do
  @moduledoc """
  Health check utilities for Docker, Kubernetes, and monitoring.

  Provides multiple levels of health checks:

  - `check/0` - CLI entry point for Docker health checks
  - `basic/0` - Quick liveness check (is the app running?)
  - `ready/0` - Readiness check (can the app serve traffic?)
  - `deep/0` - Deep check (all dependencies operational?)
  """

  alias HexHub.Upstream

  @type health_result :: %{
          status: :healthy | :degraded | :unhealthy,
          checks: map(),
          timestamp: DateTime.t()
        }

  @doc """
  CLI entry point for health checks (used by Docker HEALTHCHECK).
  """
  @spec check() :: no_return()
  def check do
    case basic() do
      %{status: :healthy} ->
        IO.puts("OK")
        System.halt(0)

      %{status: status, checks: checks} ->
        IO.puts("#{status}: #{inspect(checks)}")
        System.halt(1)
    end
  end

  @doc """
  Basic liveness check - is the application running?
  """
  @spec basic() :: health_result()
  def basic do
    mnesia_check = check_mnesia()

    status = if mnesia_check.healthy, do: :healthy, else: :unhealthy

    %{
      status: status,
      checks: %{mnesia: mnesia_check},
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Readiness check - can the application serve traffic?
  Checks Mnesia tables are loaded and ready.
  """
  @spec ready() :: health_result()
  def ready do
    mnesia_check = check_mnesia()
    tables_check = check_mnesia_tables()

    status =
      cond do
        not mnesia_check.healthy -> :unhealthy
        not tables_check.healthy -> :unhealthy
        true -> :healthy
      end

    %{
      status: status,
      checks: %{
        mnesia: mnesia_check,
        tables: tables_check
      },
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Deep health check - all dependencies operational?
  Includes storage, upstream, and optional services.
  """
  @spec deep() :: health_result()
  def deep do
    mnesia_check = check_mnesia()
    tables_check = check_mnesia_tables()
    storage_check = check_storage()
    upstream_check = check_upstream()

    all_checks = %{
      mnesia: mnesia_check,
      tables: tables_check,
      storage: storage_check,
      upstream: upstream_check
    }

    # Determine overall status
    critical_healthy = mnesia_check.healthy and tables_check.healthy
    all_healthy = critical_healthy and storage_check.healthy and upstream_check.healthy

    status =
      cond do
        not critical_healthy -> :unhealthy
        not all_healthy -> :degraded
        true -> :healthy
      end

    %{
      status: status,
      checks: all_checks,
      timestamp: DateTime.utc_now()
    }
  end

  ## Private check functions

  defp check_mnesia do
    case :mnesia.system_info(:is_running) do
      :yes ->
        %{healthy: true, message: "Mnesia is running"}

      status ->
        %{healthy: false, message: "Mnesia status: #{status}"}
    end
  rescue
    e ->
      %{healthy: false, message: "Mnesia check failed: #{inspect(e)}"}
  end

  defp check_mnesia_tables do
    tables = HexHub.Mnesia.tables()

    case :mnesia.wait_for_tables(tables, 1000) do
      :ok ->
        %{healthy: true, message: "All #{length(tables)} tables ready"}

      {:timeout, remaining} ->
        %{healthy: false, message: "Timeout waiting for tables: #{inspect(remaining)}"}

      {:error, reason} ->
        %{healthy: false, message: "Table error: #{inspect(reason)}"}
    end
  rescue
    e ->
      %{healthy: false, message: "Table check failed: #{inspect(e)}"}
  end

  defp check_storage do
    storage_type = Application.get_env(:hex_hub, :storage_type, :local)

    case storage_type do
      :local ->
        check_local_storage()

      :s3 ->
        check_s3_storage()
    end
  end

  defp check_local_storage do
    path = Application.get_env(:hex_hub, :storage_path, "priv/storage")

    cond do
      not File.exists?(path) ->
        # Try to create it
        case File.mkdir_p(path) do
          :ok -> %{healthy: true, message: "Local storage created at #{path}"}
          {:error, reason} -> %{healthy: false, message: "Cannot create storage: #{reason}"}
        end

      not File.dir?(path) ->
        %{healthy: false, message: "Storage path is not a directory"}

      true ->
        # Check write permissions with a test file
        test_file = Path.join(path, ".health_check")

        case File.write(test_file, "ok") do
          :ok ->
            File.rm(test_file)
            %{healthy: true, message: "Local storage writable at #{path}"}

          {:error, reason} ->
            %{healthy: false, message: "Storage not writable: #{reason}"}
        end
    end
  rescue
    e ->
      %{healthy: false, message: "Storage check failed: #{inspect(e)}"}
  end

  defp check_s3_storage do
    bucket = Application.get_env(:hex_hub, :s3_bucket)

    if bucket do
      # Try to list objects (limited to 1) to verify connectivity
      case ExAws.S3.list_objects(bucket, max_keys: 1) |> ExAws.request() do
        {:ok, _} ->
          %{healthy: true, message: "S3 bucket #{bucket} accessible"}

        {:error, {:http_error, status, _}} ->
          %{healthy: false, message: "S3 HTTP error: #{status}"}

        {:error, reason} ->
          %{healthy: false, message: "S3 error: #{inspect(reason)}"}
      end
    else
      %{healthy: false, message: "S3 bucket not configured"}
    end
  rescue
    e ->
      %{healthy: false, message: "S3 check failed: #{inspect(e)}"}
  end

  defp check_upstream do
    if Upstream.enabled?() do
      # Try to fetch a known package to verify connectivity
      case Upstream.fetch_package("jason") do
        {:ok, _} ->
          %{healthy: true, message: "Upstream hex.pm reachable"}

        {:error, reason} ->
          %{healthy: false, message: "Upstream error: #{inspect(reason)}"}
      end
    else
      %{healthy: true, message: "Upstream disabled (skipped)"}
    end
  rescue
    e ->
      %{healthy: false, message: "Upstream check failed: #{inspect(e)}"}
  end
end
