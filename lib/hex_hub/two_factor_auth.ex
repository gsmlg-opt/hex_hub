defmodule HexHub.TwoFactorAuth do
  @moduledoc """
  Two-Factor Authentication (2FA) implementation using TOTP (Time-based One-Time Password).

  This module provides functionality for:
  - Generating TOTP secrets
  - Verifying TOTP codes
  - Managing recovery codes
  - Enabling/disabling 2FA for users
  """

  alias HexHub.Users

  @issuer "HexHub"
  @recovery_code_count 10
  @recovery_code_length 8

  @doc """
  Generate a new TOTP secret for a user.
  """
  @spec generate_secret(String.t()) ::
          {:ok, %{secret: String.t(), uri: String.t(), qr_code: String.t()}}
          | {:error, String.t()}
  def generate_secret(username) do
    case Users.get_user(username) do
      {:ok, user} ->
        secret = NimbleTOTP.secret()

        uri =
          NimbleTOTP.otpauth_uri(
            "totp:#{@issuer}:#{user.email}",
            secret,
            issuer: @issuer,
            label: user.username,
            period: 30
          )

        # Generate QR code for easy scanning
        qr_svg =
          uri
          |> QRCode.create()
          |> QRCode.Render.Svg.create(%QRCode.Render.SvgSettings{})
          |> elem(1)
          |> Base.encode64()

        {:ok,
         %{
           secret: Base.encode32(secret),
           uri: uri,
           qr_code: "data:image/svg+xml;base64,#{qr_svg}"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Enable 2FA for a user with the provided secret and verification code.
  """
  @spec enable_2fa(String.t(), String.t(), String.t()) ::
          {:ok, %{recovery_codes: list(String.t())}} | {:error, String.t()}
  def enable_2fa(username, secret, verification_code) do
    with {:ok, _user} <- Users.get_user(username),
         :ok <- verify_code(secret, verification_code) do
      # Generate recovery codes
      recovery_codes = generate_recovery_codes()
      hashed_codes = Enum.map(recovery_codes, &Bcrypt.hash_pwd_salt/1)

      # Update user record with 2FA enabled
      case update_user_2fa(username, secret, true, hashed_codes) do
        :ok ->
          {:ok, %{recovery_codes: recovery_codes}}

        error ->
          error
      end
    else
      {:error, :invalid_code} ->
        {:error, "Invalid verification code"}

      error ->
        error
    end
  end

  @doc """
  Disable 2FA for a user after verifying their current code.
  """
  @spec disable_2fa(String.t(), String.t()) :: :ok | {:error, String.t()}
  def disable_2fa(username, verification_code) do
    with {:ok, user} <- get_user_with_2fa(username),
         true <- user.totp_enabled,
         :ok <- verify_code(user.totp_secret, verification_code) do
      update_user_2fa(username, nil, false, [])
    else
      false ->
        {:error, "2FA is not enabled for this user"}

      {:error, :invalid_code} ->
        {:error, "Invalid verification code"}

      error ->
        error
    end
  end

  @doc """
  Verify a TOTP code for a user.
  """
  @spec verify_user_code(String.t(), String.t()) :: :ok | {:error, atom()}
  def verify_user_code(username, code) do
    with {:ok, user} <- get_user_with_2fa(username),
         true <- user.totp_enabled do
      verify_code(user.totp_secret, code)
    else
      false ->
        {:error, :not_enabled}

      error ->
        error
    end
  end

  @doc """
  Verify a recovery code for a user.
  """
  @spec verify_recovery_code(String.t(), String.t()) :: :ok | {:error, String.t()}
  def verify_recovery_code(username, recovery_code) do
    with {:ok, user} <- get_user_with_2fa(username),
         true <- user.totp_enabled,
         {:ok, remaining_codes} <-
           check_and_consume_recovery_code(user.recovery_codes, recovery_code) do
      # Update user with remaining recovery codes
      update_user_recovery_codes(username, remaining_codes)
      :ok
    else
      false ->
        {:error, "2FA is not enabled for this user"}

      {:error, :invalid_code} ->
        {:error, "Invalid recovery code"}

      error ->
        error
    end
  end

  @doc """
  Generate new recovery codes for a user (requires current 2FA code).
  """
  @spec regenerate_recovery_codes(String.t(), String.t()) ::
          {:ok, list(String.t())} | {:error, String.t()}
  def regenerate_recovery_codes(username, verification_code) do
    with {:ok, user} <- get_user_with_2fa(username),
         true <- user.totp_enabled,
         :ok <- verify_code(user.totp_secret, verification_code) do
      recovery_codes = generate_recovery_codes()
      hashed_codes = Enum.map(recovery_codes, &Bcrypt.hash_pwd_salt/1)

      case update_user_recovery_codes(username, hashed_codes) do
        :ok ->
          {:ok, recovery_codes}

        error ->
          error
      end
    else
      false ->
        {:error, "2FA is not enabled for this user"}

      {:error, :invalid_code} ->
        {:error, "Invalid verification code"}

      error ->
        error
    end
  end

  @doc """
  Check if 2FA is enabled for a user.
  """
  @spec enabled?(String.t()) :: boolean()
  def enabled?(username) do
    case get_user_with_2fa(username) do
      {:ok, user} -> user.totp_enabled == true
      _ -> false
    end
  end

  # Private functions

  defp verify_code(secret, code) do
    secret_binary = Base.decode32!(secret)

    # Allow for time drift (previous, current, and next 30-second windows)
    valid? =
      NimbleTOTP.valid?(secret_binary, code) ||
        NimbleTOTP.valid?(secret_binary, code, time: System.system_time(:second) - 30) ||
        NimbleTOTP.valid?(secret_binary, code, time: System.system_time(:second) + 30)

    if valid?, do: :ok, else: {:error, :invalid_code}
  end

  defp generate_recovery_codes do
    for _ <- 1..@recovery_code_count do
      :crypto.strong_rand_bytes(@recovery_code_length)
      |> Base.encode32(padding: false)
      |> String.slice(0, @recovery_code_length)
      |> String.downcase()
    end
  end

  defp check_and_consume_recovery_code(hashed_codes, recovery_code) do
    matching_code =
      Enum.find(hashed_codes, fn hashed ->
        Bcrypt.verify_pass(recovery_code, hashed)
      end)

    if matching_code do
      remaining_codes = List.delete(hashed_codes, matching_code)
      {:ok, remaining_codes}
    else
      {:error, :invalid_code}
    end
  end

  defp get_user_with_2fa(username) do
    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({:users, username}) do
             [
               {:users, _username, email, password_hash, totp_secret, totp_enabled,
                recovery_codes, inserted_at, updated_at}
             ] ->
               %{
                 username: username,
                 email: email,
                 password_hash: password_hash,
                 totp_secret: totp_secret,
                 totp_enabled: totp_enabled,
                 recovery_codes: recovery_codes || [],
                 inserted_at: inserted_at,
                 updated_at: updated_at
               }

             [] ->
               nil
           end
         end) do
      {:atomic, nil} ->
        {:error, :not_found}

      {:atomic, user} ->
        {:ok, user}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp update_user_2fa(username, secret, enabled, recovery_codes) do
    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({:users, username}) do
             [
               {:users, username, email, password_hash, _old_secret, _old_enabled, _old_codes,
                inserted_at, _updated_at}
             ] ->
               HexHub.Database.write({
                 :users,
                 username,
                 email,
                 password_hash,
                 secret,
                 enabled,
                 recovery_codes,
                 inserted_at,
                 DateTime.utc_now()
               })

             [] ->
               {:error, :not_found}
           end
         end) do
      {:atomic, :ok} -> :ok
      {:atomic, error} -> error
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp update_user_recovery_codes(username, recovery_codes) do
    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({:users, username}) do
             [
               {:users, username, email, password_hash, secret, enabled, _old_codes, inserted_at,
                _updated_at}
             ] ->
               HexHub.Database.write({
                 :users,
                 username,
                 email,
                 password_hash,
                 secret,
                 enabled,
                 recovery_codes,
                 inserted_at,
                 DateTime.utc_now()
               })

             [] ->
               {:error, :not_found}
           end
         end) do
      {:atomic, :ok} -> :ok
      {:atomic, error} -> error
      {:aborted, reason} -> {:error, reason}
    end
  end
end
