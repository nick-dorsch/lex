defmodule Lex do
  @moduledoc """
  Lex - A reading and vocabulary learning application.
  """

  def start(_type, _args) do
    children = [
      LexWeb.Telemetry,
      {Phoenix.PubSub, name: Lex.PubSub}
    ]

    opts = [strategy: :one_for_one, name: Lex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
