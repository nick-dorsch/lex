defmodule Lex.TestLLMStreamingPlug do
  use Plug.Router

  @counter __MODULE__.RequestCounter

  plug(:match)
  plug(:dispatch)

  post "/chat/completions" do
    request_number = increment_request_count()
    maybe_sleep_before_response(mode(), request_number)

    force_unauthorized? = mode() == :always_unauthorized

    if force_unauthorized? do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
    else
      should_close? = close_connection_for_request?(mode(), request_number)

      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.put_resp_header("cache-control", "no-cache")
        |> maybe_put_connection_close_header(should_close?)
        |> Plug.Conn.send_chunked(200)

      {:ok, conn} =
        Plug.Conn.chunk(
          conn,
          "data: {\"choices\":[{\"delta\":{\"content\":\"hola\"}}]}\n\n"
        )

      {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
      conn
    end
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end

  def ensure_counter! do
    case Process.whereis(@counter) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> %{count: 0, mode: :normal} end, name: @counter)
        :ok

      _pid ->
        Agent.update(@counter, fn _ -> %{count: 0, mode: :normal} end)
    end
  end

  def request_count do
    Agent.get(@counter, & &1.count)
  end

  def set_mode(mode)
      when mode in [
             :normal,
             :always_unauthorized,
             :close_after_response,
             :close_first_response_only,
             :delay_second_response_once
           ] do
    Agent.update(@counter, fn state -> %{state | mode: mode} end)
  end

  defp close_connection_for_request?(:close_after_response, _request_number), do: true
  defp close_connection_for_request?(:close_first_response_only, 1), do: true
  defp close_connection_for_request?(_mode, _request_number), do: false

  defp maybe_sleep_before_response(:delay_second_response_once, 2), do: Process.sleep(700)
  defp maybe_sleep_before_response(_mode, _request_number), do: :ok

  defp maybe_put_connection_close_header(conn, true) do
    Plug.Conn.put_resp_header(conn, "connection", "close")
  end

  defp maybe_put_connection_close_header(conn, false), do: conn

  defp mode do
    Agent.get(@counter, & &1.mode)
  end

  defp increment_request_count do
    Agent.get_and_update(@counter, fn state ->
      next_count = state.count + 1
      {next_count, %{state | count: next_count}}
    end)
  end
end
