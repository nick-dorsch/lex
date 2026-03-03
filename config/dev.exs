import Config

config :logger, :console, format: "[$level] $message\n"

config :phoenix, stacktrace_depth: 20

config :lex, LexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: [
    tailwind: {Tailwind, :install_and_run, [:lex, ~w(--watch)]}
  ],
  secret_key_base: "dev_secret_key_base_not_for_production_64_bytes_long_needed_for_encryption",
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/lex_web/(live|components)/.*(ex|heex)$"
    ]
  ]

config :lex, Lex.Repo,
  database: Path.expand("../priv/repo/lex_dev.db", __DIR__),
  pool_size: 5,
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :lex, :dev, debug: true
