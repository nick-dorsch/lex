defmodule Lex.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    # Start a database sandbox connection
    pid = Sandbox.start_owner!(Lex.Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(pid)
    end)

    :ok
  end
end
