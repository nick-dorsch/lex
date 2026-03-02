import Config

config :lex,
  ecto_repos: [Lex.Repo],
  calibre_library_path: "~/CalibreLibrary"

config :lex, Lex.Repo, adapter: Ecto.Adapters.SQLite3

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
