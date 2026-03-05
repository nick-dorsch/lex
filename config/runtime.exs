import Config

if System.get_env("PHX_SERVER") do
  config :lex, LexWeb.Endpoint, server: true
end

config :lex, :calibre_library_path, System.get_env("CALIBRE_LIBRARY_PATH", "~/Calibre Library")

if config_env() == :prod do
  database_path = Path.expand("~/.lex/lex.db")

  File.mkdir_p!(Path.dirname(database_path))

  config :lex, :ecto_query_timeout, 60_000

  config :lex, Lex.Repo,
    database: database_path,
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
