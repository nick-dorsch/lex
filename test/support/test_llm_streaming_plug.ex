defmodule Lex.TestLLMStreamingPlug do
  use Plug.Router

  @counter __MODULE__.RequestCounter

  plug(:match)
  plug(:dispatch)

  post "/chat/completions" do
    increment_request_count()

    force_unauthorized? = mode() == :always_unauthorized

    if force_unauthorized? do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
    else
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.put_resp_header("cache-control", "no-cache")
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

  def set_mode(mode) when mode in [:normal, :always_unauthorized] do
    Agent.update(@counter, fn state -> %{state | mode: mode} end)
  end

  defp mode do
    Agent.get(@counter, & &1.mode)
  end

  defp increment_request_count do
    Agent.update(@counter, fn state -> %{state | count: state.count + 1} end)
  end
end
