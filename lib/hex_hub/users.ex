defmodule HexHub.Users do
  @moduledoc """
  User management functions with Mnesia storage.
  """

  @type user :: %{
          username: String.t(),
          email: String.t(),
          password_hash: String.t(),
          service_account: boolean(),
          deactivated_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @table :users

  # Reserved usernames that cannot be registered by regular users
  @reserved_usernames ["anonymous", "admin", "system", "hexhub"]

  @doc """
  Reset test data - mainly for testing purposes.
  """
  def reset_test_store do
    # For testing, we'll clear the Mnesia table
    :mnesia.clear_table(@table)
    :ok
  end

  @doc """
  Create a new user with hashed password.
  """
  @spec create_user(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, user()} | {:error, String.t()}
  def create_user(username, email, password, opts \\ []) do
    with :ok <- validate_username(username),
         :ok <- validate_email(email),
         :ok <- validate_password(password),
         :ok <- check_username_availability(username),
         :ok <- check_email_availability(email) do
      password_hash = Bcrypt.hash_pwd_salt(password)
      now = DateTime.utc_now()
      service_account = Keyword.get(opts, :service_account, false)

      # Store user in Mnesia with new schema
      case :mnesia.transaction(fn ->
             :mnesia.write(
               {@table, username, email, password_hash, nil, false, [], service_account, nil, now,
                now}
             )
           end) do
        {:atomic, :ok} ->
          {:ok,
           %{
             username: username,
             email: email,
             password_hash: password_hash,
             service_account: service_account,
             deactivated_at: nil,
             inserted_at: now,
             updated_at: now
           }}

        {:aborted, reason} ->
          {:error, "Failed to create user: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a service account.
  Service accounts bypass rate limiting and are meant for CI/CD automation.
  """
  @spec create_service_account(String.t(), String.t()) :: {:ok, user()} | {:error, String.t()}
  def create_service_account(username, description) do
    # Service accounts use a special email format and strong random password
    email = "service+#{username}@hexhub.local"
    password = :crypto.strong_rand_bytes(32) |> Base.encode64()

    with {:ok, user} <- create_user(username, email, password, service_account: true) do
      # Store the description in audit log
      HexHub.Audit.log_event(
        "service_account.created",
        "user",
        username,
        %{
          description: description,
          email: email
        },
        nil
      )

      # Return the password once for initial setup
      {:ok, Map.put(user, :api_key, password)}
    end
  end

  @doc """
  Get user by username or email.
  """
  @spec get_user(String.t()) :: {:ok, user()} | {:error, :not_found}
  def get_user(username_or_email) do
    # Query Mnesia by username first, then by email if not found
    case :mnesia.transaction(fn ->
           case :mnesia.read(@table, username_or_email) do
             [
               {@table, username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
                service_account, deactivated_at, inserted_at, updated_at}
             ] ->
               {:ok,
                {username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
                 service_account, deactivated_at, inserted_at, updated_at}}

             [] ->
               # If not found by username, try email
               :mnesia.index_read(@table, username_or_email, :email)
           end
         end) do
      {:atomic, {:ok, user_tuple}} ->
        {:ok, user_to_map(user_tuple)}

      {:atomic,
       [
         {@table, username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
          service_account, deactivated_at, inserted_at, updated_at}
       ]} ->
        {:ok,
         user_to_map(
           {username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
            service_account, deactivated_at, inserted_at, updated_at}
         )}

      {:atomic, []} ->
        {:error, :not_found}

      {:aborted, _reason} ->
        {:error, :not_found}
    end
  end

  @doc """
  Authenticate user with username/email and password.
  """
  @spec authenticate(String.t(), String.t()) :: {:ok, user()} | {:error, :invalid_credentials}
  def authenticate(username_or_email, password) do
    case get_user(username_or_email) do
      {:ok, user} ->
        if Bcrypt.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end

      {:error, _} ->
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Update user email.
  """
  @spec update_email(String.t(), String.t()) :: {:ok, user()} | {:error, String.t()}
  def update_email(username, new_email) do
    with :ok <- validate_email(new_email),
         :ok <- check_email_availability(new_email) do
      case :mnesia.transaction(fn ->
             case :mnesia.read(@table, username) do
               [
                 {@table, old_username, _old_email, password_hash, totp_secret, totp_enabled,
                  recovery_codes, service_account, deactivated_at, inserted_at, _updated_at}
               ] ->
                 updated_user =
                   {@table, old_username, new_email, password_hash, totp_secret, totp_enabled,
                    recovery_codes, service_account, deactivated_at, inserted_at,
                    DateTime.utc_now()}

                 :mnesia.write(updated_user)

                 {:ok,
                  {old_username, new_email, password_hash, totp_secret, totp_enabled,
                   recovery_codes, service_account, deactivated_at, inserted_at,
                   DateTime.utc_now()}}

               [] ->
                 {:error, "User not found"}
             end
           end) do
        {:atomic, {:ok, user_tuple}} ->
          {:ok, user_to_map(user_tuple)}

        {:atomic, {:error, reason}} ->
          {:error, reason}

        {:aborted, reason} ->
          {:error, "Failed to update email: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update user password.
  """
  @spec update_password(String.t(), String.t()) :: {:ok, user()} | {:error, String.t()}
  def update_password(username, new_password) do
    with :ok <- validate_password(new_password) do
      case :mnesia.transaction(fn ->
             case :mnesia.read(@table, username) do
               [
                 {@table, username, email, _old_hash, totp_secret, totp_enabled, recovery_codes,
                  service_account, deactivated_at, inserted_at, _updated_at}
               ] ->
                 password_hash = Bcrypt.hash_pwd_salt(new_password)

                 updated_user =
                   {@table, username, email, password_hash, totp_secret, totp_enabled,
                    recovery_codes, service_account, deactivated_at, inserted_at,
                    DateTime.utc_now()}

                 :mnesia.write(updated_user)

                 {:ok,
                  {username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
                   service_account, deactivated_at, inserted_at, DateTime.utc_now()}}

               [] ->
                 {:error, "User not found"}
             end
           end) do
        {:atomic, {:ok, user_tuple}} ->
          {:ok, user_to_map(user_tuple)}

        {:atomic, {:error, reason}} ->
          {:error, reason}

        {:aborted, reason} ->
          {:error, "Failed to update password: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List all users (for admin purposes).
  """
  @spec list_users() :: {:ok, [user()]}
  def list_users() do
    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn {_, username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
                 service_account, deactivated_at, inserted_at, updated_at},
                acc ->
               [
                 user_to_map(
                   {username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
                    service_account, deactivated_at, inserted_at, updated_at}
                 )
                 | acc
               ]
             end,
             [],
             @table
           )
         end) do
      {:atomic, users} -> {:ok, users}
      {:aborted, reason} -> {:error, "Failed to list users: #{inspect(reason)}"}
    end
  end

  @doc """
  Get user by API key.
  """
  @spec get_user_by_api_key(String.t()) :: {:ok, user()} | {:error, :not_found}
  def get_user_by_api_key(api_key) do
    case HexHub.ApiKeys.validate_key(api_key) do
      {:ok, %{username: username}} ->
        get_user(username)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Check if user is a service account.
  """
  @spec is_service_account?(String.t()) :: boolean()
  def is_service_account?(username) do
    case :mnesia.transaction(fn ->
           case :mnesia.read(@table, username) do
             [
               {@table, _username, _email, _password_hash, _totp_secret, _totp_enabled,
                _recovery_codes, service_account, _deactivated_at, _inserted_at, _updated_at}
             ] ->
               service_account == true

             [] ->
               false
           end
         end) do
      {:atomic, result} -> result
      {:aborted, _} -> false
    end
  end

  @doc """
  Deactivate a user account.
  """
  @spec deactivate_user(String.t()) :: :ok | {:error, String.t()}
  def deactivate_user(username) do
    case :mnesia.transaction(fn ->
           case :mnesia.read(@table, username) do
             [
               {@table, username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
                service_account, _deactivated_at, inserted_at, _updated_at}
             ] ->
               :mnesia.write({
                 @table,
                 username,
                 email,
                 password_hash,
                 totp_secret,
                 totp_enabled,
                 recovery_codes,
                 service_account,
                 DateTime.utc_now(),
                 inserted_at,
                 DateTime.utc_now()
               })

             [] ->
               {:error, "User not found"}
           end
         end) do
      {:atomic, :ok} -> :ok
      {:atomic, error} -> error
      {:aborted, reason} -> {:error, "Failed to deactivate user: #{inspect(reason)}"}
    end
  end

  @doc """
  List all service accounts.
  """
  @spec list_service_accounts() :: list(user())
  def list_service_accounts() do
    case :mnesia.transaction(fn ->
           :mnesia.index_read(@table, true, :service_account)
         end) do
      {:atomic, users} ->
        Enum.map(users, &user_to_map/1)

      {:aborted, _} ->
        []
    end
  end

  @doc """
  Check if a username is a system user (cannot be deleted or modified).
  """
  @spec is_system_user?(String.t()) :: boolean()
  def is_system_user?(username) do
    String.downcase(username) == "anonymous"
  end

  @doc """
  Delete a user by username.
  System users (like "anonymous") cannot be deleted.
  """
  @spec delete_user(String.t()) :: :ok | {:error, String.t()}
  def delete_user(username) do
    if is_system_user?(username) do
      {:error, "Cannot delete system user"}
    else
      case :mnesia.transaction(fn ->
             case :mnesia.read(@table, username) do
               [_user] ->
                 :mnesia.delete({@table, username})

               [] ->
                 {:error, "User not found"}
             end
           end) do
        {:atomic, :ok} -> :ok
        {:atomic, {:error, reason}} -> {:error, reason}
        {:aborted, reason} -> {:error, "Failed to delete user: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Update a user's details.
  System users (like "anonymous") cannot be modified.
  """
  @spec update_user(String.t(), map()) :: {:ok, user()} | {:error, String.t()}
  def update_user(username, _params) do
    if is_system_user?(username) do
      {:error, "Cannot modify system user"}
    else
      # For now, just return user not found - full implementation would update fields
      {:error, "User not found"}
    end
  end

  @doc """
  Ensure the anonymous system user exists.
  Creates the user if it doesn't exist. Called at application startup.
  """
  @spec ensure_anonymous_user() :: :ok | {:error, String.t()}
  def ensure_anonymous_user do
    case get_user("anonymous") do
      {:ok, _user} ->
        :ok

      {:error, :not_found} ->
        # Create anonymous user as a service account
        # Use a special email and random password (never used for login)
        email = "anonymous@hexhub.local"
        password = :crypto.strong_rand_bytes(32) |> Base.encode64()
        now = DateTime.utc_now()

        case :mnesia.transaction(fn ->
               :mnesia.write(
                 {@table, "anonymous", email, Bcrypt.hash_pwd_salt(password), nil, false, [],
                  true, nil, now, now}
               )
             end) do
          {:atomic, :ok} ->
            # Emit telemetry event
            :telemetry.execute(
              [:hex_hub, :anonymous_user, :created],
              %{},
              %{username: "anonymous"}
            )

            HexHub.Telemetry.log(:info, :user, "Anonymous system user created", %{
              username: "anonymous"
            })

            :ok

          {:aborted, reason} ->
            {:error, "Failed to create anonymous user: #{inspect(reason)}"}
        end
    end
  end

  ## Helper functions

  defp user_to_map(
         {@table, username, email, password_hash, _totp_secret, _totp_enabled, _recovery_codes,
          service_account, deactivated_at, inserted_at, updated_at}
       ) do
    %{
      username: username,
      email: email,
      password_hash: password_hash,
      service_account: service_account || false,
      deactivated_at: deactivated_at,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end

  # Legacy compatibility for old tuple format
  defp user_to_map(
         {username, email, password_hash, totp_secret, totp_enabled, recovery_codes,
          service_account, deactivated_at, inserted_at, updated_at}
       ) do
    %{
      username: username,
      email: email,
      password_hash: password_hash,
      totp_secret: totp_secret,
      totp_enabled: totp_enabled || false,
      recovery_codes: recovery_codes || [],
      service_account: service_account || false,
      deactivated_at: deactivated_at,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end

  ## Validation functions

  defp validate_username(username) do
    cond do
      String.downcase(username) in @reserved_usernames ->
        {:error, "Username is reserved"}

      String.length(username) < 3 ->
        {:error, "Username must be at least 3 characters"}

      String.length(username) > 30 ->
        {:error, "Username must be at most 30 characters"}

      not String.match?(username, ~r/^[A-Za-z0-9_\-.]+$/) ->
        {:error, "Username can only contain letters, numbers, underscores, hyphens, and dots"}

      true ->
        :ok
    end
  end

  defp validate_email(email) do
    if not String.match?(email, ~r/^[^\s]+@[^\s]+$/) do
      {:error, "Invalid email format"}
    else
      :ok
    end
  end

  defp validate_password(password) do
    if String.length(password) < 8 do
      {:error, "Password must be at least 8 characters"}
    else
      :ok
    end
  end

  defp check_username_availability(username) do
    case :mnesia.transaction(fn ->
           :mnesia.read(@table, username)
         end) do
      {:atomic, []} -> :ok
      {:atomic, [_]} -> {:error, "Username already taken"}
      {:aborted, reason} -> {:error, "Failed to check username availability: #{inspect(reason)}"}
    end
  end

  defp check_email_availability(email) do
    case :mnesia.transaction(fn ->
           :mnesia.index_read(@table, email, :email)
         end) do
      {:atomic, []} -> :ok
      {:atomic, [_]} -> {:error, "Email already taken"}
      {:aborted, reason} -> {:error, "Failed to check email availability: #{inspect(reason)}"}
    end
  end
end
