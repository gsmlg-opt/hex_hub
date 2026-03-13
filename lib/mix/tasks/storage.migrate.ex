defmodule Mix.Tasks.Storage.Migrate do
  @moduledoc """
  Migrates storage from flat `packages/` and `docs/` directories to the new
  `hosted/` and `cached/` structure.

  Files are moved based on Mnesia package metadata:
  - Packages with source `:local` -> `hosted/`
  - Packages with source `:cached` -> `cached/`

  This task is idempotent — it skips if old directories don't exist or are empty.

  ## Usage

      mix storage.migrate
  """
  @shortdoc "Migrate storage to hosted/cached directory structure"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    HexHub.Storage.migrate_directory_structure()
    Mix.shell().info("Storage migration complete.")
  end
end
