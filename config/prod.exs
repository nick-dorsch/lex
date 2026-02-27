import Config

config :logger,
  level: :info,
  compile_time_purge_levels: [:debug, :info]

config :lex, LexWeb.Endpoint,
  http: [port: System.get_env("PORT") || 4000],
  url: [host: System.get_env("HOST") || "localhost"],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true
