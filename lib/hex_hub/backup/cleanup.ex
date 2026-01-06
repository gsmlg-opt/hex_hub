defmodule HexHub.Backup.Cleanup do
  @moduledoc """
  GenServer that periodically cleans up expired backups.

  Runs daily to delete backups older than the configured retention period
  (default 30 days).
  """

  use GenServer

  require Logger

  alias HexHub.Backup

  @cleanup_interval :timer.hours(24)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers a manual cleanup run.
  """
  def run_cleanup do
    GenServer.cast(__MODULE__, :cleanup)
  end

  @doc """
  Gets the next scheduled cleanup time.
  """
  def next_cleanup_at do
    GenServer.call(__MODULE__, :next_cleanup_at)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Schedule first cleanup after a short delay (allow system to start)
    schedule_cleanup(5_000)

    {:ok, %{next_cleanup_at: nil}}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    do_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    do_cleanup()
    next_at = schedule_cleanup()
    {:noreply, %{state | next_cleanup_at: next_at}}
  end

  @impl true
  def handle_call(:next_cleanup_at, _from, state) do
    {:reply, state.next_cleanup_at, state}
  end

  # Private functions

  defp schedule_cleanup(delay \\ @cleanup_interval) do
    Process.send_after(self(), :cleanup, delay)
    DateTime.add(DateTime.utc_now(), div(delay, 1000), :second)
  end

  defp do_cleanup do
    HexHub.Telemetry.log(:info, :backup, "Starting backup cleanup", %{})

    case Backup.cleanup_expired_backups() do
      {:ok, count} ->
        if count > 0 do
          HexHub.Telemetry.log(:info, :backup, "Cleaned up expired backups", %{count: count})
        else
          HexHub.Telemetry.log(:debug, :backup, "No expired backups to clean up", %{})
        end

        emit_cleanup_completed(count)

      {:error, reason} ->
        HexHub.Telemetry.log(:error, :backup, "Backup cleanup failed", %{reason: inspect(reason)})
    end
  end

  defp emit_cleanup_completed(count) do
    :telemetry.execute(
      [:hex_hub, :backup, :cleanup],
      %{deleted_count: count},
      %{}
    )
  end
end
