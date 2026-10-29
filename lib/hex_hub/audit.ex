defmodule HexHub.Audit do
  @moduledoc """
  Audit logging system for security and compliance.
  """

  alias HexHub.Users

  @audit_table :audit_logs

  @type audit_event :: %{
          id: String.t(),
          timestamp: DateTime.t(),
          user_id: String.t() | nil,
          action: String.t(),
          resource_type: String.t(),
          resource_id: String.t(),
          details: map(),
          ip_address: String.t() | nil,
          user_agent: String.t() | nil
        }

  @doc """
  Initialize audit logging system.
  """
  def init() do
    case HexHub.Database.create_table(@audit_table,
           attributes: [
             :id,
             :timestamp,
             :user_id,
             :action,
             :resource_type,
             :resource_id,
             :details,
             :ip_address,
             :user_agent
           ],
           type: :ordered_set,
           disc_copies: [node()]
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, _}} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Log an audit event.
  """
  @spec log_event(String.t(), String.t(), String.t(), map(), Plug.Conn.t() | nil) ::
          :ok | {:error, String.t()}
  def log_event(action, resource_type, resource_id, details, conn \\ nil) do
    user_id = get_user_id(conn)
    ip_address = get_ip_address(conn)
    user_agent = get_user_agent(conn)

    event = {
      @audit_table,
      UUID.uuid4(),
      DateTime.utc_now(),
      user_id,
      action,
      resource_type,
      resource_id,
      details,
      ip_address,
      user_agent
    }

    case HexHub.Database.transaction(fn ->
           HexHub.Database.write(event)
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, "Failed to log audit event: #{inspect(reason)}"}
    end
  end

  @doc """
  Get audit logs for a specific resource.
  """
  @spec get_audit_logs(String.t(), String.t(), integer()) ::
          {:ok, [audit_event()]} | {:error, String.t()}
  def get_audit_logs(resource_type, resource_id, limit \\ 100) do
    case HexHub.Database.transaction(fn ->
           HexHub.Database.foldl(
             fn {:audit_logs, id, timestamp, user_id, action, rt, rid, details, ip, ua}, acc ->
               if rt == resource_type and rid == resource_id do
                 [
                   %{
                     id: id,
                     timestamp: timestamp,
                     user_id: user_id,
                     action: action,
                     resource_type: rt,
                     resource_id: rid,
                     details: details,
                     ip_address: ip,
                     user_agent: ua
                   }
                   | acc
                 ]
               else
                 acc
               end
             end,
             [],
             @audit_table
           )
           |> Enum.take(limit)
           |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
         end) do
      {:atomic, logs} -> {:ok, logs}
      {:aborted, reason} -> {:error, "Failed to get audit logs: #{inspect(reason)}"}
    end
  end

  @doc """
  Get all audit logs with pagination.
  """
  @spec get_all_audit_logs(integer(), integer()) :: {:ok, [audit_event()]} | {:error, String.t()}
  def get_all_audit_logs(limit \\ 100, offset \\ 0) do
    case HexHub.Database.transaction(fn ->
           HexHub.Database.foldl(
             fn {:audit_logs, id, timestamp, user_id, action, rt, rid, details, ip, ua}, acc ->
               [
                 %{
                   id: id,
                   timestamp: timestamp,
                   user_id: user_id,
                   action: action,
                   resource_type: rt,
                   resource_id: rid,
                   details: details,
                   ip_address: ip,
                   user_agent: ua
                 }
                 | acc
               ]
             end,
             [],
             @audit_table
           )
           |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
           |> Enum.drop(offset)
           |> Enum.take(limit)
         end) do
      {:atomic, logs} -> {:ok, logs}
      {:aborted, reason} -> {:error, "Failed to get audit logs: #{inspect(reason)}"}
    end
  end

  defp get_user_id(nil), do: nil

  defp get_user_id(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Users.get_user_by_api_key(token) do
          {:ok, user} -> user.username
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_ip_address(nil), do: nil

  defp get_ip_address(conn) do
    conn.remote_ip
    |> :inet_parse.ntoa()
    |> to_string()
  end

  defp get_user_agent(nil), do: nil

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      [] -> nil
    end
  end
end
