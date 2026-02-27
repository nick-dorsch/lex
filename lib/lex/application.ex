defmodule Lex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Lex.Repo,
      LexWeb.Telemetry,
      {Phoenix.PubSub, name: Lex.PubSub},
      LexWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Lex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
