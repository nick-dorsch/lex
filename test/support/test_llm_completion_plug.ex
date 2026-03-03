defmodule Lex.TestLLMCompletionPlug do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/chat/completions" do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(
      200,
      ~s({"choices":[{"message":{"content":"hola"}}],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}})
    )
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
