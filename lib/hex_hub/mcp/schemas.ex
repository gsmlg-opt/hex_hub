defmodule HexHub.MCP.Schemas do
  @moduledoc """
  JSON-RPC request/response schemas and validation.

  Provides schema definitions and validation functions for MCP protocol
  messages following JSON-RPC 2.0 specification.
  """

  @doc """
  JSON-RPC request schema
  """
  def request_schema do
    %{
      "type" => "object",
      "required" => ["jsonrpc", "method"],
      "properties" => %{
        "jsonrpc" => %{"type" => "string"},
        "method" => %{"type" => "string"},
        "params" => %{"type" => "object"},
        "id" => %{
          "oneOf" => [
            %{"type" => "string"},
            %{"type" => "number"},
            %{"type" => "null"}
          ]
        }
      }
    }
  end

  @doc """
  Tool call request schema
  """
  def tool_call_schema do
    %{
      "type" => "object",
      "required" => ["jsonrpc", "method", "params"],
      "properties" => %{
        "jsonrpc" => %{"type" => "string", "enum" => ["2.0"]},
        "method" => %{"type" => "string", "pattern" => "^tools/call/"},
        "params" => %{
          "type" => "object",
          "required" => ["arguments"],
          "properties" => %{
            "arguments" => %{
              "type" => "object"
            }
          }
        },
        "id" => %{
          "oneOf" => [
            %{"type" => "string"},
            %{"type" => "number"},
            %{"type" => "null"}
          ]
        }
      }
    }
  end

  @doc """
  Tool definition schema
  """
  def tool_definition_schema do
    %{
      "type" => "object",
      "required" => ["name", "description", "inputSchema"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "inputSchema" => %{"type" => "object"}
      }
    }
  end

  @doc """
  Parse and validate JSON-RPC request
  """
  def parse_request(raw_request) when is_binary(raw_request) do
    case Jason.decode(raw_request) do
      {:ok, parsed} -> validate_basic_request(parsed)
      {:error, _} -> {:error, :parse_error}
    end
  end

  def parse_request(raw_request) when is_map(raw_request) do
    validate_basic_request(raw_request)
  end

  def parse_request(_), do: {:error, :parse_error}

  @doc """
  Validate request against specific schemas
  """
  def validate_request(request) do
    if is_tool_call?(request) do
      case validate_against_schema(request, tool_call_schema()) do
        :ok -> {:ok, request}
        {:ok, validated} -> {:ok, validated}
        {:error, reason} -> {:error, reason}
      end
    else
      case validate_against_schema(request, request_schema()) do
        :ok -> {:ok, request}
        {:ok, validated} -> {:ok, validated}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Validate tool arguments against tool schema
  """
  def validate_tool_arguments(tool_name, arguments) do
    case HexHub.MCP.Server.get_tool_schema(tool_name) do
      {:ok, tool} -> validate_against_schema(arguments, tool.input_schema)
      {:error, _} -> {:error, :tool_not_found}
    end
  end

  # Private functions

  defp validate_basic_request(request) do
    with :ok <- validate_required_fields(request),
         :ok <- validate_jsonrpc_version(request) do
      {:ok, request}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_required_fields(request) do
    case Map.has_key?(request, "jsonrpc") and Map.has_key?(request, "method") do
      true -> :ok
      false -> {:error, :missing_required_fields}
    end
  end

  defp validate_jsonrpc_version(request) do
    case Map.get(request, "jsonrpc") do
      "2.0" -> :ok
      _ -> {:error, :invalid_jsonrpc_version}
    end
  end

  defp is_tool_call?(request) do
    method = Map.get(request, "method", "")
    String.starts_with?(method, "tools/call/")
  end

  defp validate_against_schema(data, schema) do
    # For now, we'll do basic validation
    # In a production implementation, you might want to use a JSON schema validator
    validate_schema_basic(data, schema)
  end

  defp validate_schema_basic(data, schema) do
    case validate_type(data, schema) do
      :ok -> validate_properties(data, schema)
      error -> error
    end
  end

  defp validate_type(data, %{"type" => "object"}) when is_map(data), do: :ok
  defp validate_type(data, %{"type" => "array"}) when is_list(data), do: :ok
  defp validate_type(data, %{"type" => "string"}) when is_binary(data), do: :ok
  defp validate_type(data, %{"type" => "number"}) when is_number(data), do: :ok
  defp validate_type(data, %{"type" => "integer"}) when is_integer(data), do: :ok
  defp validate_type(data, %{"type" => "boolean"}) when is_boolean(data), do: :ok
  defp validate_type(nil, %{"type" => "null"}), do: :ok

  # Handle oneOf schemas (e.g., for id field that can be string, number, or null)
  defp validate_type(data, %{"oneOf" => schemas}) when is_list(schemas) do
    if Enum.any?(schemas, fn schema -> validate_type(data, schema) == :ok end) do
      :ok
    else
      {:error, :type_mismatch}
    end
  end

  defp validate_type(_data, %{"type" => _type}) do
    {:error, :type_mismatch}
  end

  defp validate_type(_, _), do: {:error, :type_mismatch}

  defp validate_properties(data, %{"type" => "object"} = schema) do
    required_fields = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    # Check required fields
    missing_fields = Enum.reject(required_fields, &Map.has_key?(data, &1))

    if missing_fields != [] do
      {:error, :missing_required_fields}
    else
      # Validate each property that has a schema
      Enum.reduce_while(data, :ok, fn {key, value}, _acc ->
        case Map.get(properties, key) do
          nil ->
            {:cont, :ok}

          prop_schema ->
            case validate_schema_basic(value, prop_schema) do
              :ok -> {:cont, :ok}
              error -> {:halt, error}
            end
        end
      end)
    end
  end

  defp validate_properties(_data, _schema), do: :ok

  @doc """
  Build tool input schema for Elixir types
  """
  def build_tool_schema(params_spec) do
    properties =
      Enum.into(params_spec, %{}, fn {name, opts} ->
        type = Keyword.get(opts, :type, :string)
        _required = Keyword.get(opts, :required, false)
        description = Keyword.get(opts, :description, "")

        {to_string(name),
         %{
           "type" => type_to_json_schema(type),
           "description" => description
         }}
      end)

    required_fields =
      Enum.filter(params_spec, fn {_name, opts} ->
        Keyword.get(opts, :required, false)
      end)
      |> Enum.map(fn {name, _opts} -> to_string(name) end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields
    }
  end

  defp type_to_json_schema(:string), do: "string"
  defp type_to_json_schema(:integer), do: "integer"
  defp type_to_json_schema(:number), do: "number"
  defp type_to_json_schema(:boolean), do: "boolean"
  defp type_to_json_schema(:array), do: "array"
  defp type_to_json_schema(:object), do: "object"
  defp type_to_json_schema(_), do: "string"
end
