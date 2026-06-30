defmodule HexHub.Assets.DuskmoonBundlerWatcher do
  @moduledoc false

  def run(opts) when is_list(opts) do
    case DuskmoonBundler.Watcher.start_link(opts) do
      {:ok, _pid} ->
        Process.sleep(:infinity)

      {:error, {:already_started, _pid}} ->
        Process.sleep(:infinity)

      {:error, reason} ->
        raise "failed to start DuskmoonBundler watcher: #{inspect(reason)}"
    end
  end
end
