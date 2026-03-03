defmodule Lex.LLM.SessionConnectionOwner do
  @moduledoc """
  Owns transport connection state for a single LiveView session.

  This process keeps one reusable connection in memory, allows callers to
  mark it unhealthy, and ensures cleanup when the owner terminates.
  """

  use GenServer

  @type connection :: term()
  @type state :: %{
          connection: connection() | nil,
          healthy?: boolean(),
          unhealthy_reason: term() | nil,
          close_fun: (connection() -> any()),
          handoff_fun: (connection(), pid() -> :ok | {:error, term()})
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec get_or_connect(GenServer.server(), (-> {:ok, connection()} | {:error, term()})) ::
          {:ok, connection()} | {:error, term()}
  def get_or_connect(owner, connect_fun) when is_function(connect_fun, 0) do
    GenServer.call(owner, {:get_or_connect, connect_fun})
  end

  @spec mark_unhealthy(GenServer.server(), term()) :: :ok
  def mark_unhealthy(owner, reason \\ :unhealthy) do
    GenServer.call(owner, {:mark_unhealthy, reason})
  end

  @spec reconnect(GenServer.server(), (-> {:ok, connection()} | {:error, term()})) ::
          {:ok, connection()} | {:error, term()}
  def reconnect(owner, connect_fun) when is_function(connect_fun, 0) do
    GenServer.call(owner, {:reconnect, connect_fun})
  end

  @spec current_connection(GenServer.server()) :: connection() | nil
  def current_connection(owner) do
    GenServer.call(owner, :current_connection)
  end

  @spec put_connection(GenServer.server(), connection()) :: :ok
  def put_connection(owner, conn) do
    GenServer.call(owner, {:put_connection, conn})
  end

  @impl true
  def init(opts) do
    close_fun = Keyword.get(opts, :close_fun, fn _conn -> :ok end)
    handoff_fun = Keyword.get(opts, :handoff_fun, &default_handoff_fun/2)

    {:ok,
     %{
       connection: nil,
       healthy?: false,
       unhealthy_reason: nil,
       close_fun: close_fun,
       handoff_fun: handoff_fun
     }}
  end

  @impl true
  def handle_call(
        {:get_or_connect, _connect_fun},
        {caller_pid, _tag},
        %{connection: conn, healthy?: true} = state
      )
      when not is_nil(conn) do
    case handoff_connection(state, conn, caller_pid) do
      :ok ->
        {:reply, {:ok, conn}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{close_connection(state) | unhealthy_reason: reason}}
    end
  end

  def handle_call({:get_or_connect, connect_fun}, {caller_pid, _tag}, state) do
    case connect_fun.() do
      {:ok, conn} ->
        case handoff_connection(state, conn, caller_pid) do
          :ok ->
            {:reply, {:ok, conn},
             %{state | connection: conn, healthy?: true, unhealthy_reason: nil}}

          {:error, reason} ->
            _ = state.close_fun.(conn)

            {:reply, {:error, reason},
             %{state | connection: nil, healthy?: false, unhealthy_reason: reason}}
        end

      {:error, reason} ->
        {:reply, {:error, reason},
         %{state | connection: nil, healthy?: false, unhealthy_reason: reason}}
    end
  end

  @impl true
  def handle_call({:mark_unhealthy, reason}, _from, state) do
    new_state = close_connection(state)
    {:reply, :ok, %{new_state | unhealthy_reason: reason}}
  end

  def handle_call({:reconnect, connect_fun}, _from, state) do
    state = close_connection(state)

    case connect_fun.() do
      {:ok, conn} ->
        {:reply, {:ok, conn}, %{state | connection: conn, healthy?: true, unhealthy_reason: nil}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | unhealthy_reason: reason}}
    end
  end

  def handle_call(:current_connection, _from, state) do
    {:reply, state.connection, state}
  end

  def handle_call({:put_connection, conn}, _from, state) do
    {:reply, :ok, %{state | connection: conn, healthy?: true, unhealthy_reason: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    _ = close_connection(state)
    :ok
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp close_connection(%{connection: nil} = state), do: %{state | healthy?: false}

  defp close_connection(%{connection: conn, close_fun: close_fun} = state) do
    _ = close_fun.(conn)
    %{state | connection: nil, healthy?: false}
  end

  defp handoff_connection(%{handoff_fun: handoff_fun}, conn, caller_pid) do
    handoff_fun.(conn, caller_pid)
  end

  defp default_handoff_fun(conn, caller_pid) do
    if is_map(conn) and Map.has_key?(conn, :socket) do
      case Mint.HTTP.controlling_process(conn, caller_pid) do
        :ok -> :ok
        {:ok, _conn} -> :ok
        {:error, _conn, reason} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
