defmodule HexHubWeb.ApiError do
  @moduledoc """
  Centralized API error response helper.

  Provides consistent error response formats for all API endpoints.
  All error responses follow the pattern:

      %{
        "status" => 400..599,
        "message" => "Human-readable error message",
        "errors" => %{} | nil  # Optional field-specific errors
      }

  ## Usage

      import HexHubWeb.ApiError

      # Simple error
      conn |> error_response(:not_found, "Package not found")

      # With field errors
      conn |> error_response(:unprocessable_entity, "Validation failed", %{
        name: ["can't be blank"],
        version: ["is invalid"]
      })

  ## Standard HTTP status codes

  - 400 :bad_request - Invalid request syntax or parameters
  - 401 :unauthorized - Authentication required
  - 403 :forbidden - Authenticated but not authorized
  - 404 :not_found - Resource not found
  - 409 :conflict - Resource conflict (e.g., duplicate)
  - 422 :unprocessable_entity - Validation errors
  - 429 :too_many_requests - Rate limit exceeded
  - 500 :internal_server_error - Server error
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @type error_status ::
          :bad_request
          | :unauthorized
          | :forbidden
          | :not_found
          | :conflict
          | :unprocessable_entity
          | :too_many_requests
          | :internal_server_error
          | pos_integer()

  @doc """
  Send an error response with the given status and message.
  """
  @spec error_response(Plug.Conn.t(), error_status(), String.t()) :: Plug.Conn.t()
  def error_response(conn, status, message) do
    status_code = status_to_code(status)

    conn
    |> put_status(status)
    |> json(%{
      "status" => status_code,
      "message" => message
    })
  end

  @doc """
  Send an error response with field-specific errors.
  """
  @spec error_response(Plug.Conn.t(), error_status(), String.t(), map()) :: Plug.Conn.t()
  def error_response(conn, status, message, errors) when is_map(errors) do
    status_code = status_to_code(status)

    conn
    |> put_status(status)
    |> json(%{
      "status" => status_code,
      "message" => message,
      "errors" => errors
    })
  end

  @doc """
  Send a not found error.
  """
  @spec not_found(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def not_found(conn, resource \\ "Resource") do
    error_response(conn, :not_found, "#{resource} not found")
  end

  @doc """
  Send an unauthorized error.
  """
  @spec unauthorized(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def unauthorized(conn, message \\ "Authentication required") do
    error_response(conn, :unauthorized, message)
  end

  @doc """
  Send a forbidden error.
  """
  @spec forbidden(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def forbidden(conn, message \\ "Access denied") do
    error_response(conn, :forbidden, message)
  end

  @doc """
  Send a bad request error.
  """
  @spec bad_request(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def bad_request(conn, message) do
    error_response(conn, :bad_request, message)
  end

  @doc """
  Send a validation error with field-specific errors.
  """
  @spec validation_error(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def validation_error(conn, errors) when is_map(errors) do
    error_response(conn, :unprocessable_entity, "Validation failed", errors)
  end

  @doc """
  Send an internal server error.
  """
  @spec internal_error(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def internal_error(conn, message \\ "Internal server error") do
    error_response(conn, :internal_server_error, message)
  end

  @doc """
  Send a conflict error.
  """
  @spec conflict(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def conflict(conn, message) do
    error_response(conn, :conflict, message)
  end

  @doc """
  Send a rate limit exceeded error.
  """
  @spec rate_limited(Plug.Conn.t(), integer()) :: Plug.Conn.t()
  def rate_limited(conn, retry_after \\ 60) do
    conn
    |> put_resp_header("retry-after", to_string(retry_after))
    |> error_response(:too_many_requests, "Rate limit exceeded")
  end

  ## Private helpers

  defp status_to_code(:bad_request), do: 400
  defp status_to_code(:unauthorized), do: 401
  defp status_to_code(:forbidden), do: 403
  defp status_to_code(:not_found), do: 404
  defp status_to_code(:conflict), do: 409
  defp status_to_code(:unprocessable_entity), do: 422
  defp status_to_code(:too_many_requests), do: 429
  defp status_to_code(:internal_server_error), do: 500
  defp status_to_code(code) when is_integer(code), do: code
end
