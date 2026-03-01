defmodule LexWeb.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :lex,
    render_errors: [
      formats: [html: LexWeb.ErrorHTML],
      layout: false
    ]

  @session_options [
    store: :cookie,
    key: "_lex_key",
    signing_salt: "signing_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :lex,
    gzip: false,
    only: LexWeb.static_paths()
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(LexWeb.Router)
end
