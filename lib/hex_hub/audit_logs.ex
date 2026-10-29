defmodule HexHub.AuditLogs do
  @moduledoc """
  Enhanced audit logging system for comprehensive security and compliance tracking.

  Tracks:
  - All API operations with request/response details
  - Package operations (publish, retire, delete)
  - User authentication and authorization events
  - API key usage and management
  - Download statistics
  - Security events (failed auth, rate limiting, blocked IPs)
  """

  alias HexHub.Audit

  # Audit event actions
  @actions %{
    # Authentication events
    "auth.login" => "User login",
    "auth.logout" => "User logout",
    "auth.failed" => "Failed authentication attempt",
    "auth.api_key_used" => "API key authentication",
    "auth.2fa_required" => "2FA verification required",
    "auth.2fa_verified" => "2FA successfully verified",
    "auth.2fa_failed" => "2FA verification failed",

    # Package events
    "package.published" => "Package published",
    "package.updated" => "Package updated",
    "package.retired" => "Package retired",
    "package.unretired" => "Package unretired",
    "package.deleted" => "Package deleted",
    "package.downloaded" => "Package downloaded",
    "package.docs_uploaded" => "Documentation uploaded",
    "package.docs_deleted" => "Documentation deleted",
    "package.ownership_added" => "Owner added to package",
    "package.ownership_removed" => "Owner removed from package",

    # User events
    "user.created" => "User account created",
    "user.updated" => "User account updated",
    "user.deactivated" => "User account deactivated",
    "user.reactivated" => "User account reactivated",
    "user.password_changed" => "Password changed",
    "user.email_changed" => "Email address changed",
    "user.2fa_enabled" => "2FA enabled",
    "user.2fa_disabled" => "2FA disabled",

    # API key events
    "api_key.created" => "API key created",
    "api_key.used" => "API key used",
    "api_key.revoked" => "API key revoked",
    "api_key.expired" => "API key expired",

    # Security events
    "security.rate_limit" => "Rate limit exceeded",
    "security.ip_blocked" => "IP address blocked",
    "security.ip_unblocked" => "IP address unblocked",
    "security.suspicious_activity" => "Suspicious activity detected",
    "security.invalid_request" => "Invalid request blocked",

    # Service account events
    "service_account.created" => "Service account created",
    "service_account.used" => "Service account authenticated",
    "service_account.deactivated" => "Service account deactivated"
  }

  @doc """
  Log an audit event with enhanced details.
  """
  @spec log_action(String.t(), String.t(), String.t(), String.t(), map(), Plug.Conn.t() | nil) ::
          :ok | {:error, String.t()}
  def log_action(_user_id, action, resource_type, resource_id, details \\ %{}, conn \\ nil) do
    enhanced_details = build_enhanced_details(details, conn)

    Audit.log_event(action, resource_type, resource_id, enhanced_details, conn)

    # Track API key usage
    if conn && action == "auth.api_key_used" do
      update_api_key_last_used(conn)
    end

    # Track download statistics
    if action == "package.downloaded" do
      update_download_stats(resource_id, details)
    end

    :ok
  end

  @doc """
  Query audit logs with filtering and pagination.
  """
  @spec query_logs(map()) :: {:ok, list(map())} | {:error, String.t()}
  def query_logs(filters \\ %{}) do
    # Extract filter parameters
    user_id = filters[:user_id]
    action = filters[:action]
    resource_type = filters[:resource_type]
    resource_id = filters[:resource_id]
    category = filters[:category]
    from = filters[:from] || DateTime.add(DateTime.utc_now(), -30, :day)
    to = filters[:to] || DateTime.utc_now()
    limit = filters[:limit] || 100
    offset = filters[:offset] || 0

    case HexHub.Database.transaction(fn ->
           # Build match specification for filtering
           match_spec = build_match_spec(user_id, action, resource_type, resource_id, from, to)

           # Query with filters
           results = HexHub.Database.select(:audit_logs, match_spec)

           # Filter by category if specified
           results =
             if category do
               filter_by_category(results, category)
             else
               results
             end

           # Sort by timestamp descending
           results =
             Enum.sort_by(
               results,
               fn {_, _, timestamp, _, _, _, _, _, _, _} ->
                 timestamp
               end,
               {:desc, DateTime}
             )

           # Apply pagination
           results
           |> Enum.drop(offset)
           |> Enum.take(limit)
           |> Enum.map(&format_audit_log/1)
         end) do
      {:atomic, results} -> {:ok, results}
      {:aborted, reason} -> {:error, "Failed to query audit logs: #{inspect(reason)}"}
    end
  end

  @doc """
  Get audit logs for a specific user.
  """
  @spec get_user_audit_logs(String.t(), map()) :: {:ok, list(map())} | {:error, String.t()}
  def get_user_audit_logs(username, opts \\ %{}) do
    query_logs(Map.put(opts, :user_id, username))
  end

  @doc """
  Get audit logs for a specific package.
  """
  @spec get_package_audit_logs(String.t(), map()) :: {:ok, list(map())} | {:error, String.t()}
  def get_package_audit_logs(package_name, opts \\ %{}) do
    query_logs(
      Map.merge(opts, %{
        resource_type: "package",
        resource_id: package_name
      })
    )
  end

  @doc """
  Get security-related audit logs.
  """
  @spec get_security_logs(map()) :: {:ok, list(map())} | {:error, String.t()}
  def get_security_logs(opts \\ %{}) do
    query_logs(Map.put(opts, :category, :security))
  end

  @doc """
  Get download statistics for a package.
  """
  @spec get_download_stats(String.t(), String.t() | nil) :: map()
  def get_download_stats(package_name, version \\ nil) do
    result =
      if version do
        get_single_version_stats(package_name, version)
      else
        get_aggregate_stats(package_name)
      end

    case result do
      {:atomic, stats} -> stats
      {:aborted, _} -> %{day: 0, week: 0, all: 0}
    end
  end

  @doc """
  Export audit logs for compliance reporting.
  """
  @spec export_logs(map(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def export_logs(filters \\ %{}, format \\ "json") do
    case query_logs(filters) do
      {:ok, logs} ->
        case format do
          "json" ->
            {:ok, Jason.encode!(logs, pretty: true)}

          "csv" ->
            csv_content = build_csv(logs)
            {:ok, csv_content}

          _ ->
            {:error, "Unsupported export format: #{format}"}
        end

      error ->
        error
    end
  end

  # Private functions

  defp build_enhanced_details(details, nil), do: details

  defp build_enhanced_details(details, conn) do
    Map.merge(details, %{
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string,
      user_agent: get_user_agent(conn),
      ip_address: get_ip_address(conn),
      timestamp: DateTime.utc_now()
    })
  end

  defp update_api_key_last_used(conn) do
    case conn.assigns[:api_key_name] do
      nil ->
        :ok

      key_name ->
        HexHub.Database.transaction(fn ->
          case HexHub.Database.read({:api_keys, key_name}) do
            [
              {:api_keys, name, username, secret_hash, permissions, revoked_at, inserted_at,
               _updated_at}
            ] ->
              HexHub.Database.write({
                :api_keys,
                name,
                username,
                secret_hash,
                permissions,
                revoked_at,
                inserted_at,
                DateTime.utc_now()
              })

            _ ->
              :ok
          end
        end)
    end
  end

  defp update_download_stats(resource_id, _details) do
    {package_name, version} = parse_resource_id(resource_id)

    HexHub.Database.transaction(fn ->
      key = {package_name, version}

      case HexHub.Database.read({:package_downloads, key}) do
        [{:package_downloads, ^key, _pkg, _ver, day, week, all}] ->
          HexHub.Database.write({
            :package_downloads,
            key,
            package_name,
            version,
            day + 1,
            week + 1,
            all + 1
          })

        [] ->
          HexHub.Database.write({
            :package_downloads,
            key,
            package_name,
            version,
            1,
            1,
            1
          })
      end
    end)
  end

  defp parse_resource_id(resource_id) do
    case String.split(resource_id, ":") do
      [package, version] -> {package, version}
      [package] -> {package, "latest"}
      _ -> {resource_id, "latest"}
    end
  end

  defp build_match_spec(user_id, action, resource_type, resource_id, from, to) do
    # Build a match specification for mnesia:select
    # This is a simplified version - you might need to adjust based on your exact needs
    [
      {
        {:audit_logs, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"},
        build_guards(user_id, action, resource_type, resource_id, from, to),
        [:"$$"]
      }
    ]
  end

  defp build_guards(user_id, action, resource_type, resource_id, from, to) do
    guards = []

    guards = if user_id, do: [{:==, :"$3", user_id} | guards], else: guards
    guards = if action, do: [{:==, :"$4", action} | guards], else: guards
    guards = if resource_type, do: [{:==, :"$5", resource_type} | guards], else: guards
    guards = if resource_id, do: [{:==, :"$6", resource_id} | guards], else: guards
    guards = [{:>=, :"$2", from} | guards]
    guards = [{:"=<", :"$2", to} | guards]

    guards
  end

  defp filter_by_category(results, category) do
    category_actions = get_category_actions(category)

    Enum.filter(results, fn {_, _, _, action, _, _, _, _, _, _} ->
      action in category_actions
    end)
  end

  defp get_category_actions(:auth),
    do: [
      "auth.login",
      "auth.logout",
      "auth.failed",
      "auth.api_key_used",
      "auth.2fa_required",
      "auth.2fa_verified",
      "auth.2fa_failed"
    ]

  defp get_category_actions(:package),
    do: [
      "package.published",
      "package.updated",
      "package.retired",
      "package.unretired",
      "package.deleted",
      "package.downloaded",
      "package.docs_uploaded",
      "package.docs_deleted",
      "package.ownership_added",
      "package.ownership_removed"
    ]

  defp get_category_actions(:user),
    do: [
      "user.created",
      "user.updated",
      "user.deactivated",
      "user.reactivated",
      "user.password_changed",
      "user.email_changed",
      "user.2fa_enabled",
      "user.2fa_disabled"
    ]

  defp get_category_actions(:security),
    do: [
      "security.rate_limit",
      "security.ip_blocked",
      "security.ip_unblocked",
      "security.suspicious_activity",
      "security.invalid_request"
    ]

  defp get_category_actions(_), do: []

  defp format_audit_log(
         {:audit_logs, id, timestamp, user_id, action, resource_type, resource_id, details,
          ip_address, user_agent}
       ) do
    %{
      id: id,
      timestamp: timestamp,
      user_id: user_id,
      action: action,
      action_description: @actions[action] || action,
      resource_type: resource_type,
      resource_id: resource_id,
      details: details,
      ip_address: ip_address,
      user_agent: user_agent
    }
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent | _] -> user_agent
      [] -> nil
    end
  end

  defp get_ip_address(conn) do
    forwarded_for = Plug.Conn.get_req_header(conn, "x-forwarded-for")

    case forwarded_for do
      [ips | _] ->
        ips
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> Tuple.to_list()
        |> Enum.join(".")
    end
  end

  defp build_csv(logs) do
    headers = "ID,Timestamp,User,Action,Resource Type,Resource ID,IP Address,User Agent\n"

    rows =
      Enum.map_join(logs, "\n", fn log ->
        [
          log.id,
          log.timestamp,
          log.user_id || "",
          log.action_description,
          log.resource_type,
          log.resource_id,
          log.ip_address || "",
          log.user_agent || ""
        ]
        |> Enum.map_join(",", &escape_csv/1)
      end)

    headers <> rows
  end

  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp escape_csv(value), do: to_string(value)

  defp get_single_version_stats(package_name, version) do
    HexHub.Database.transaction(fn ->
      case HexHub.Database.read({:package_downloads, {package_name, version}}) do
        [{:package_downloads, _key, _pkg, _ver, day_count, week_count, all_count}] ->
          %{day: day_count, week: week_count, all: all_count}

        [] ->
          %{day: 0, week: 0, all: 0}
      end
    end)
  end

  defp get_aggregate_stats(package_name) do
    HexHub.Database.transaction(fn ->
      HexHub.Database.foldl(
        fn {:package_downloads, {pkg, _ver}, _pkg2, _ver2, day, week, all}, acc ->
          if pkg == package_name do
            %{
              day: acc.day + day,
              week: acc.week + week,
              all: acc.all + all
            }
          else
            acc
          end
        end,
        %{day: 0, week: 0, all: 0},
        :package_downloads
      )
    end)
  end
end
