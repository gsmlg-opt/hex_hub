defmodule HexHub.ApiKeys do
  @moduledoc """
  API key management for authentication.
  """

  @type api_key :: %{
          name: String.t(),
          username: String.t(),
          secret_hash: String.t(),
          permissions: [String.t()],
          revoked_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @table :api_keys

  @doc """
  Reset test data - mainly for testing purposes.
  """
  def reset_test_store do
    :mnesia.clear_table(@table)
    :ok
  end

  @doc """
  Generate a new API key for a user.
  """
  @spec generate_key(String.t(), String.t(), [String.t()]) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_key(name, username, permissions \\ ["read", "write"]) do
    with {:ok, _user} <- HexHub.Users.get_user(username) do
      key = generate_random_key()
      secret_hash = Bcrypt.hash_pwd_salt(key)
      now = DateTime.utc_now()

      api_key = {
        @table,
        name,
        username,
        secret_hash,
        permissions,
        # revoked_at
        nil,
        now,
        now
      }

      case :mnesia.transaction(fn ->
             :mnesia.write(api_key)
           end) do
        {:atomic, :ok} -> {:ok, key}
        {:aborted, reason} -> {:error, "Failed to generate key: #{inspect(reason)}"}
      end
    else
      {:error, _} -> {:error, "User not found"}
    end
  end

  @doc """
  Validate an API key and return user info.

  Uses ETS cache for performance - avoids O(n) bcrypt comparisons on every request.
  """
  @spec validate_key(String.t()) ::
          {:ok, %{username: String.t(), permissions: [String.t()]}}
          | {:error, :invalid_key | :revoked_key}
  def validate_key(key) do
    # Check cache first for fast path
    case HexHub.ApiKeyCache.get(key) do
      {:ok, cached_result} ->
        {:ok, cached_result}

      :not_found ->
        # Cache miss - do full validation
        validate_key_uncached(key)
    end
  end

  # Full validation without cache
  defp validate_key_uncached(key) do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(&check_key_match(key, &1, &2), nil, @table)
         end) do
      {:atomic, {:ok, %{username: username, permissions: permissions, revoked_at: nil}}} ->
        # Cache the successful validation
        HexHub.ApiKeyCache.put(key, username, permissions)
        {:ok, %{username: username, permissions: permissions}}

      {:atomic, {:ok, %{revoked_at: revoked_at}}} when not is_nil(revoked_at) ->
        {:error, :revoked_key}

      {:atomic, nil} ->
        {:error, :invalid_key}

      {:aborted, _reason} ->
        {:error, :invalid_key}
    end
  end

  # Helper function to check if a key matches during foldl
  defp check_key_match(_key, _record, {:ok, _} = acc), do: acc

  defp check_key_match(
         key,
         {_, _name, username, secret_hash, permissions, revoked_at, _inserted_at, _updated_at},
         nil
       ) do
    if Bcrypt.verify_pass(key, secret_hash) do
      {:ok, %{username: username, permissions: permissions, revoked_at: revoked_at}}
    else
      nil
    end
  end

  @doc """
  Revoke an API key.
  """
  @spec revoke_key(String.t(), String.t()) :: :ok | {:error, String.t()}
  def revoke_key(name, username) do
    case :mnesia.transaction(fn ->
           case :mnesia.read(@table, name) do
             [{@table, name, ^username, secret_hash, permissions, nil, inserted_at, _updated_at}] ->
               updated_key = {
                 @table,
                 name,
                 username,
                 secret_hash,
                 permissions,
                 DateTime.utc_now(),
                 inserted_at,
                 DateTime.utc_now()
               }

               :mnesia.write(updated_key)
               :ok

             [
               {@table, _name, ^username, _secret_hash, _permissions, revoked_at, _inserted_at,
                _updated_at}
             ]
             when not is_nil(revoked_at) ->
               {:error, "Key already revoked"}

             [] ->
               {:error, "Key not found"}

             [
               {@table, _name, _other_username, _secret_hash, _permissions, _revoked_at,
                _inserted_at, _updated_at}
             ] ->
               {:error, "Key does not belong to user"}
           end
         end) do
      {:atomic, :ok} ->
        # Invalidate cache for this user (their key is now revoked)
        HexHub.ApiKeyCache.invalidate_user(username)
        :ok

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, "Failed to revoke key: #{inspect(reason)}"}
    end
  end

  @doc """
  List all API keys for a user.
  """
  @spec list_keys(String.t()) :: {:ok, [api_key()]} | {:error, String.t()}
  def list_keys(username) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object({@table, :_, username, :_, :_, :_, :_, :_})
         end) do
      {:atomic, keys} ->
        {:ok, Enum.map(keys, &api_key_to_map/1)}

      {:aborted, reason} ->
        {:error, "Failed to list keys: #{inspect(reason)}"}
    end
  end

  @doc """
  Check if user has required permission.
  """
  @spec has_permission?(String.t(), String.t(), String.t()) :: boolean()
  def has_permission?(key, username, permission) do
    case validate_key(key) do
      {:ok, %{username: key_username, permissions: permissions}} ->
        key_username == username and permission in permissions

      _ ->
        false
    end
  end

  ## Helper functions

  defp generate_random_key() do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp api_key_to_map(
         {@table, name, username, secret_hash, permissions, revoked_at, inserted_at, updated_at}
       ) do
    %{
      name: name,
      username: username,
      secret_hash: secret_hash,
      permissions: permissions,
      revoked_at: revoked_at,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end
end
