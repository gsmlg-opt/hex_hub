defmodule HexHub.Backup.Manifest do
  @moduledoc """
  Handles backup manifest generation and parsing.

  The manifest is a JSON file stored within the backup tar archive
  that describes the backup contents and metadata.
  """

  @manifest_version "1.0"

  @type t :: %{
          version: String.t(),
          hex_hub_version: String.t(),
          created_at: String.t(),
          created_by: String.t(),
          contents: %{
            users: non_neg_integer(),
            packages: non_neg_integer(),
            releases: non_neg_integer(),
            total_size_bytes: non_neg_integer()
          },
          checksums: map()
        }

  @doc """
  Generates a manifest for a backup.

  ## Parameters

    - `created_by` - Username of the admin creating the backup
    - `contents` - Map with :users, :packages, :releases counts
    - `checksums` - Map of file paths to SHA256 checksums

  ## Returns

    A manifest map that can be encoded to JSON.
  """
  def generate(created_by, contents, checksums \\ %{}) do
    %{
      version: @manifest_version,
      hex_hub_version: hex_hub_version(),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      created_by: created_by,
      contents: %{
        users: Map.get(contents, :users, 0),
        packages: Map.get(contents, :packages, 0),
        releases: Map.get(contents, :releases, 0),
        total_size_bytes: Map.get(contents, :total_size_bytes, 0)
      },
      checksums: checksums
    }
  end

  @doc """
  Encodes a manifest to JSON.
  """
  def encode(manifest) do
    Jason.encode!(manifest, pretty: true)
  end

  @doc """
  Parses a manifest from JSON.

  Returns {:ok, manifest} or {:error, reason}.
  """
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} ->
        manifest = %{
          version: Map.get(data, "version"),
          hex_hub_version: Map.get(data, "hex_hub_version"),
          created_at: Map.get(data, "created_at"),
          created_by: Map.get(data, "created_by"),
          contents: parse_contents(Map.get(data, "contents", %{})),
          checksums: Map.get(data, "checksums", %{})
        }

        {:ok, manifest}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  @doc """
  Validates a manifest for compatibility.

  Returns :ok if the manifest is valid and compatible, or {:error, reason}.
  """
  def validate(manifest) do
    cond do
      is_nil(manifest.version) ->
        {:error, :missing_version}

      not compatible_version?(manifest.version) ->
        {:error, {:incompatible_version, manifest.version}}

      is_nil(manifest.created_at) ->
        {:error, :missing_created_at}

      true ->
        :ok
    end
  end

  @doc """
  Returns the current manifest version.
  """
  def version, do: @manifest_version

  @doc """
  Checks if a manifest version is compatible with the current version.
  """
  def compatible_version?(version) do
    # For now, only version 1.0 is supported
    # In the future, we can add migration logic for older versions
    version == @manifest_version
  end

  @doc """
  Computes SHA256 checksum of binary data.
  """
  def checksum(data) when is_binary(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  @doc """
  Verifies a checksum matches the expected value.
  """
  def verify_checksum(data, expected) do
    actual = checksum(data)
    actual == expected
  end

  # Private functions

  defp hex_hub_version do
    case :application.get_key(:hex_hub, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> "unknown"
    end
  end

  defp parse_contents(contents) when is_map(contents) do
    %{
      users: Map.get(contents, "users", 0),
      packages: Map.get(contents, "packages", 0),
      releases: Map.get(contents, "releases", 0),
      total_size_bytes: Map.get(contents, "total_size_bytes", 0)
    }
  end

  defp parse_contents(_), do: %{users: 0, packages: 0, releases: 0, total_size_bytes: 0}
end
