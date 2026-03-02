defmodule Lex.LLM.SessionConnectionOwnerTest do
  use ExUnit.Case, async: true

  alias Lex.LLM.SessionConnectionOwner

  test "get_or_connect establishes then reuses same connection" do
    {:ok, owner} = SessionConnectionOwner.start_link()

    connect_fun = fn -> {:ok, make_ref()} end

    assert {:ok, conn} = SessionConnectionOwner.get_or_connect(owner, connect_fun)
    assert {:ok, ^conn} = SessionConnectionOwner.get_or_connect(owner, connect_fun)
    assert conn == SessionConnectionOwner.current_connection(owner)
  end

  test "mark_unhealthy clears current connection" do
    {:ok, owner} = SessionConnectionOwner.start_link()
    connect_fun = fn -> {:ok, make_ref()} end

    assert {:ok, _conn} = SessionConnectionOwner.get_or_connect(owner, connect_fun)
    assert :ok = SessionConnectionOwner.mark_unhealthy(owner, :network_error)
    assert nil == SessionConnectionOwner.current_connection(owner)
  end

  test "reconnect replaces existing connection" do
    {:ok, owner} = SessionConnectionOwner.start_link()

    assert {:ok, conn1} =
             SessionConnectionOwner.get_or_connect(owner, fn -> {:ok, make_ref()} end)

    assert {:ok, conn2} = SessionConnectionOwner.reconnect(owner, fn -> {:ok, make_ref()} end)

    refute conn1 == conn2
    assert conn2 == SessionConnectionOwner.current_connection(owner)
  end

  test "owner closes active connection on terminate" do
    test_pid = self()

    close_fun = fn conn ->
      send(test_pid, {:closed, conn})
      :ok
    end

    {:ok, owner} = SessionConnectionOwner.start_link(close_fun: close_fun)

    assert {:ok, conn} = SessionConnectionOwner.get_or_connect(owner, fn -> {:ok, make_ref()} end)

    Process.monitor(owner)
    GenServer.stop(owner, :normal)

    assert_receive {:closed, ^conn}, 1000
    assert_receive {:DOWN, _ref, :process, ^owner, :normal}, 1000
  end
end
