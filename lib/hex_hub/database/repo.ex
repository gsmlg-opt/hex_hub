defmodule HexHub.Database.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :hex_hub, adapter: Ecto.Adapters.Postgres
end
