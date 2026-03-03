import Config

if System.get_env("PHX_SERVER") do
  config :lex, LexWeb.Endpoint, server: true
end

config :lex, :calibre_library_path, System.get_env("CALIBRE_LIBRARY_PATH", "~/Calibre Library")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: DATABASE_URL=sqlite3:///path/to/lex.db
      """

  config :lex, :ecto_query_timeout, 60_000

  config :lex, Lex.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :lex, LexWeb.Endpoint, secret_key_base: secret_key_base
end

# LLM Configuration
config :lex, :llm_api_key, System.get_env("LLM_API_KEY")
config :lex, :llm_provider, System.get_env("LLM_PROVIDER", "openai")
config :lex, :llm_model, System.get_env("LLM_MODEL", "gpt-4o-mini")
config :lex, :llm_base_url, System.get_env("LLM_BASE_URL", "https://api.openai.com/v1")
config :lex, :llm_timeout_ms, String.to_integer(System.get_env("LLM_TIMEOUT_MS") || "30000")
config :lex, :llm_max_tokens, String.to_integer(System.get_env("LLM_MAX_TOKENS") || "250")
