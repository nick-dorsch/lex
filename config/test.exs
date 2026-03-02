import Config

config :logger, level: :warning

config :phoenix, :json_library, Jason

config :lex, LexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_not_for_production_64_bytes_long_needed_for_encryption_keys",
  server: false,
  live_view: [signing_salt: "test_signing_salt"],
  render_errors: [
    formats: [html: LexWeb.ErrorHTML],
    layout: false
  ]

config :lex, Lex.Repo,
  database: Path.expand("../priv/repo/lex_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :lex, :test, debug: false

# LLM Configuration for tests
# Use mock client to avoid external API calls during tests
config :lex, :llm_client, Lex.LLM.ClientMock
config :lex, :llm_api_key, "test_api_key"
config :lex, :llm_base_url, "https://api.test.openai.com/v1"
config :lex, :llm_model, "gpt-4o-mini"
config :lex, :llm_timeout_ms, 5000
