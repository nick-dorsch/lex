import Config

config :lex,
  ecto_repos: [Lex.Repo],
  calibre_library_path: "~/Calibre Library"

config :lex, Lex.Repo, adapter: Ecto.Adapters.SQLite3

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :lex, LexWeb.Endpoint,
  pubsub_server: Lex.PubSub,
  live_view: [signing_salt: "GJj5zLq7-X-H5ABE"]

# Tailwind CSS configuration
config :tailwind,
  version: "3.4.0",
  lex: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
