defmodule HexHubAdminWeb.UpstreamController do
  @moduledoc """
  Admin controller for upstream configuration management.
  """

  use HexHubAdminWeb, :controller

  alias HexHub.UpstreamConfig

  plug :ensure_authenticated when action in [:index, :edit, :update]
  plug :ensure_admin when action in [:update]

  def index(conn, _params) do
    config = UpstreamConfig.get_config()

    render(conn, :index, upstream_config: config)
  end

  def edit(conn, _params) do
    config = UpstreamConfig.get_config()

    changeset = changeset(config)

    render(conn, :edit, upstream_config: config, changeset: changeset)
  end

  def update(conn, %{"upstream_config" => upstream_params}) do
    case UpstreamConfig.update_config(upstream_params) do
      :ok ->
        conn
        |> put_flash(:info, "Upstream configuration updated successfully!")
        |> redirect(to: ~p"/upstream")

      {:error, reason} ->
        config = UpstreamConfig.get_config()

        conn
        |> put_flash(:error, "Failed to update upstream configuration: #{inspect(reason)}")
        |> render(:edit, upstream_config: config, changeset: changeset(%{}, upstream_params))
    end
  end

  def test_connection(conn, _params) do
    config = UpstreamConfig.get_config()

    if config.enabled do
      # Test the connection by making a simple request to the API
      case test_upstream_connection(config) do
        :ok ->
          json(conn, %{status: "success", message: "Connection successful!"})

        {:error, reason} ->
          json(conn, %{status: "error", message: "Connection failed: #{reason}"})
      end
    else
      json(conn, %{status: "warning", message: "Upstream is disabled"})
    end
  end

  # Private functions

  defp changeset(config, params \\ %{}) do
    errors =
      []
      |> validate_required_fields(config, params)
      |> validate_url_formats(config, params)
      |> validate_numeric_ranges(config, params)

    %{
      data: config,
      params: params,
      errors: Enum.reverse(errors),
      valid?: Enum.empty?(errors)
    }
  end

  defp validate_required_fields(errors, config, params) do
    required_fields = [:enabled, :api_url, :repo_url]

    Enum.reduce(required_fields, errors, fn field, acc ->
      if is_nil(params[field]) and is_nil(config[field]) do
        [{to_string(field), "is required"} | acc]
      else
        acc
      end
    end)
  end

  defp validate_url_formats(errors, config, params) do
    api_url = params[:api_url] || config[:api_url] || ""
    repo_url = params[:repo_url] || config[:repo_url] || ""

    errors
    |> validate_url_format("api_url", api_url)
    |> validate_url_format("repo_url", repo_url)
  end

  defp validate_url_format(errors, _field, ""), do: errors

  defp validate_url_format(errors, field, url) do
    if String.match?(url, ~r/^https?:\/\//) do
      errors
    else
      [{field, "must be a valid URL"} | errors]
    end
  end

  defp validate_numeric_ranges(errors, config, params) do
    timeout = params[:timeout] || config[:timeout] || 30_000
    retry_attempts = params[:retry_attempts] || config[:retry_attempts] || 3
    retry_delay = params[:retry_delay] || config[:retry_delay] || 1_000

    errors
    |> validate_numeric_range("timeout", timeout, 1000, 300_000)
    |> validate_numeric_range("retry_attempts", retry_attempts, 1, 9)
    |> validate_numeric_range("retry_delay", retry_delay, 100, 60_000)
  end

  defp validate_numeric_range(errors, field, value, min, max) do
    if is_number(value) and value > min and value < max do
      errors
    else
      [{field, "must be between #{min} and #{max}"} | errors]
    end
  end

  defp test_upstream_connection(config) do
    url = "#{config.api_url}/api/packages?per_page=1"

    headers = [
      {"user-agent", "HexHub/0.1.0 (Connection-Test)"}
    ]

    headers =
      case config.api_key do
        nil -> headers
        api_key -> [{"authorization", "Bearer #{api_key}"} | headers]
      end

    request_opts = [
      timeout: 5000,
      headers: headers
    ]

    case HexHub.HTTPClient.get(url, request_opts) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status}} when status in [401, 403] ->
        if config.api_key do
          {:error, "Authentication failed - check API key"}
        else
          {:error, "Authentication required - API key needed"}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp ensure_authenticated(conn, _opts) do
    # This should implement your authentication logic
    # For now, we'll assume it passes
    conn
  end

  defp ensure_admin(conn, _opts) do
    # This should implement your admin authorization logic
    # For now, we'll assume it passes
    conn
  end
end
