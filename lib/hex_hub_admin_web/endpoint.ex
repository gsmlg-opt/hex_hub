defmodule HexHubAdminWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hex_hub

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_hex_hub_admin_key",
    signing_salt: "admin_signing_salt",
    same_site: "Lax"
  ]

  # LiveView socket for real-time features
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/admin" the static files from admin priv/static directory.
  plug Plug.Static,
    at: "/",
    from: :hex_hub,
    gzip: false,
    only: HexHubAdminWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  # Trust reverse proxy headers (x-forwarded-for, x-forwarded-proto, x-forwarded-port)
  plug Plug.RewriteOn, [
    :x_forwarded_for,
    :x_forwarded_host,
    :x_forwarded_port,
    :x_forwarded_proto
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug HexHubAdminWeb.Router
end
