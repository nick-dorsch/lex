defmodule Lex.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
