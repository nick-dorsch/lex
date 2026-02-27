defmodule Lex.Repo do
  use Ecto.Repo,
    otp_app: :lex,
    adapter: Ecto.Adapters.SQLite3
end
