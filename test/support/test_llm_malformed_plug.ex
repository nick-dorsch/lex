defmodule Lex.TestLLMMalformedPlug do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/chat/completions" do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, "{not-valid-json")
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
