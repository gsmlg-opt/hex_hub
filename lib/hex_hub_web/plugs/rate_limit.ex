defmodule HexHubWeb.Plugs.RateLimit do
  @moduledoc """
  Enhanced rate limiting plug with granular control per user, organization, and IP.

  Implements rate limiting similar to hex.pm:
  - User-based: 500 requests/minute
  - Organization-based: 500 requests/minute
  - IP-based: 100 requests/minute
  - Login attempts: 10/15 minutes per IP
  - 2FA attempts: 20/15 minutes per IP, 5/10 minutes per session
  """

  import Plug.Conn
  alias HexHub.BlockedAddresses

  @default_limits %{
    # 500 requests per minute
    user: {500, 60},
    # 500 requests per minute
    organization: {500, 60},
    # 100 requests per minute
    ip: {100, 60},
    # 10 attempts per 15 minutes
    login: {10, 900},
    # 20 2FA attempts per 15 minutes per IP
    tfa_ip: {20, 900},
    # 5 2FA attempts per 10 minutes per session
    tfa_session: {5, 600}
  }

  def init(opts), do: opts

  def call(conn, opts) do
    # Check if IP is blocked first
    case check_blocked_ip(conn) do
      :ok ->
        # Check if user is a service account (bypass rate limiting)
        if bypass_for_service_account?(conn) do
          conn
        else
          apply_rate_limits(conn, opts)
        end

      {:error, :blocked} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Your IP address has been blocked"})
        |> halt()
    end
  end

  defp bypass_for_service_account?(conn) do
    case conn.assigns[:current_user] do
      %{username: username} ->
        HexHub.Users.is_service_account?(username)

      _ ->
        false
    end
  end

  defp apply_rate_limits(conn, opts) do
    endpoint = opts[:endpoint] || :general
    custom_limits = opts[:limits] || %{}
    limits = Map.merge(@default_limits, custom_limits)

    # Determine which limits to apply based on the endpoint
    checks =
      case endpoint do
        :login ->
          [
            {:ip, get_ip(conn), limits.login}
          ]

        :tfa ->
          [
            {:ip, "tfa:#{get_ip(conn)}", limits.tfa_ip},
            {:session, "tfa:#{get_session_id(conn)}", limits.tfa_session}
          ]

        _ ->
          # General API endpoints
          checks = []

          # Add user-based limit if authenticated
          checks =
            if user = conn.assigns[:current_user] do
              [{:user, "user:#{user.username}", limits.user} | checks]
            else
              checks
            end

          # Add organization-based limit if applicable
          checks =
            if org = conn.assigns[:current_organization] do
              [{:organization, "org:#{org}", limits.organization} | checks]
            else
              checks
            end

          # Always add IP-based limit
          [{:ip, "ip:#{get_ip(conn)}", limits.ip} | checks]
      end

    # Check all applicable limits
    case check_all_limits(checks) do
      :ok ->
        # Increment all counters
        Enum.each(checks, fn {_type, key, _limit} ->
          increment_counter(key)
        end)

        conn

      {:error, type, remaining_time} ->
        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(remaining_time))
        |> json(%{
          error: "Rate limit exceeded",
          type: type,
          retry_after: remaining_time
        })
        |> halt()
    end
  end

  defp check_all_limits(checks) do
    Enum.reduce_while(checks, :ok, fn {type, key, {limit, window}}, _acc ->
      case check_rate_limit(key, limit, window) do
        :ok -> {:cont, :ok}
        {:error, remaining} -> {:halt, {:error, type, remaining}}
      end
    end)
  end

  defp check_rate_limit(key, limit, window) do
    now = System.system_time(:second)
    window_start = now - window

    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({:rate_limit, key}) do
             [{:rate_limit, ^key, _type, _id, count, start, _updated}]
             when start > window_start ->
               if count >= limit do
                 # Calculate remaining time until window resets
                 remaining = start + window - now
                 {:error, remaining}
               else
                 :ok
               end

             _ ->
               # No recent activity or window expired
               :ok
           end
         end) do
      {:atomic, result} -> result
      # Allow request on error
      {:aborted, _reason} -> :ok
    end
  end

  defp increment_counter(key) do
    now = System.system_time(:second)

    HexHub.Database.transaction(fn ->
      case HexHub.Database.read({:rate_limit, key}) do
        [{:rate_limit, ^key, type, id, count, start, _updated}] ->
          # Update existing counter
          HexHub.Database.write({
            :rate_limit,
            key,
            type,
            id,
            count + 1,
            start,
            DateTime.utc_now()
          })

        [] ->
          # Create new counter
          {type, id} = parse_key(key)

          HexHub.Database.write({
            :rate_limit,
            key,
            type,
            id,
            1,
            now,
            DateTime.utc_now()
          })
      end
    end)
  end

  defp parse_key(key) do
    case String.split(key, ":", parts: 2) do
      [type, id] -> {String.to_atom(type), id}
      [id] -> {:general, id}
    end
  end

  defp check_blocked_ip(conn) do
    BlockedAddresses.check_ip(get_ip(conn))
  end

  defp get_ip(conn) do
    # Try to get real IP from headers first (for proxied requests)
    forwarded_for = get_req_header(conn, "x-forwarded-for")

    ip =
      case forwarded_for do
        [ips | _] ->
          # Take the first IP from the forwarded chain
          ips
          |> String.split(",")
          |> List.first()
          |> String.trim()

        [] ->
          # Fall back to remote_ip
          conn.remote_ip
          |> Tuple.to_list()
          |> Enum.join(".")
      end

    ip
  end

  defp get_session_id(conn) do
    # Get or create a session ID for rate limiting
    case get_session(conn, :session_id) do
      nil ->
        session_id = UUID.uuid4()
        put_session(conn, :session_id, session_id)
        session_id

      session_id ->
        session_id
    end
  end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(data))
  end
end

defmodule HexHub.BlockedAddresses do
  @moduledoc """
  Module for managing blocked IP addresses.
  """

  @doc """
  Check if an IP address is blocked.
  """
  def check_ip(ip_address) do
    now = DateTime.utc_now()

    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({:blocked_addresses, ip_address}) do
             [
               {:blocked_addresses, ^ip_address, type, _reason, _blocked_at, blocked_until,
                _created_by}
             ] ->
               cond do
                 type == :allowlist ->
                   # IP is allowlisted, always allow
                   :ok

                 is_nil(blocked_until) ->
                   # Permanent block
                   {:error, :blocked}

                 DateTime.compare(now, blocked_until) == :lt ->
                   # Still within blocking period
                   {:error, :blocked}

                 true ->
                   # Block has expired, remove it
                   HexHub.Database.delete({:blocked_addresses, ip_address})
                   :ok
               end

             [] ->
               # IP not in blocked list
               :ok
           end
         end) do
      {:atomic, result} -> result
      # Allow on error
      {:aborted, _reason} -> :ok
    end
  end

  @doc """
  Block an IP address.
  """
  def block_ip(ip_address, reason, blocked_until \\ nil, created_by \\ "system") do
    HexHub.Database.transaction(fn ->
      HexHub.Database.write({
        :blocked_addresses,
        ip_address,
        :blocklist,
        reason,
        DateTime.utc_now(),
        blocked_until,
        created_by
      })
    end)
  end

  @doc """
  Allowlist an IP address (bypass rate limiting).
  """
  def allowlist_ip(ip_address, reason, created_by \\ "system") do
    HexHub.Database.transaction(fn ->
      HexHub.Database.write({
        :blocked_addresses,
        ip_address,
        :allowlist,
        reason,
        DateTime.utc_now(),
        # Allowlist doesn't expire
        nil,
        created_by
      })
    end)
  end

  @doc """
  Unblock an IP address.
  """
  def unblock_ip(ip_address) do
    HexHub.Database.transaction(fn ->
      HexHub.Database.delete({:blocked_addresses, ip_address})
    end)
  end

  @doc """
  List all blocked addresses.
  """
  def list_blocked() do
    case HexHub.Database.transaction(fn ->
           HexHub.Database.select(:blocked_addresses, [
             {
               {:"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7"},
               [{:==, :"$3", :blocklist}],
               [:"$$"]
             }
           ])
         end) do
      {:atomic, results} ->
        Enum.map(results, fn [ip, _ip2, type, reason, blocked_at, blocked_until, created_by] ->
          %{
            ip_address: ip,
            type: type,
            reason: reason,
            blocked_at: blocked_at,
            blocked_until: blocked_until,
            created_by: created_by
          }
        end)

      {:aborted, _reason} ->
        []
    end
  end
end
