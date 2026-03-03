defmodule Lex.TestLLMCompletionPlug do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/chat/completions" do
    conn =
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_chunked(200)

    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        ~s(data: {"choices":[{"delta":{"content":"hola"}}]}\n\n)
      )

    {:ok, conn} =
      Plug.Conn.chunk(
        conn,
        ~s(data: {"choices":[],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}\n\ndata: [DONE]\n\n)
      )

    conn
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
