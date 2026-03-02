defmodule LexWeb.CalibreCoverController do
  use LexWeb, :controller

  alias Lex.Library

  @max_age 7 * 24 * 60 * 60

  def show(conn, %{"token" => token}) do
    with {:ok, cover_path} <-
           Phoenix.Token.verify(LexWeb.Endpoint, "calibre_cover", token, max_age: @max_age),
         :ok <- validate_cover_path(cover_path),
         true <- File.regular?(cover_path) do
      conn
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> put_resp_content_type(MIME.from_path(cover_path), nil)
      |> send_file(200, cover_path)
    else
      _ ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp validate_cover_path(cover_path) do
    calibre_root = Library.calibre_library_path() |> Path.expand()
    expanded_cover_path = Path.expand(cover_path)

    allowed_extensions = [".jpg", ".jpeg", ".png"]

    cond do
      not Enum.any?(
        allowed_extensions,
        &String.ends_with?(String.downcase(expanded_cover_path), &1)
      ) ->
        :error

      same_or_subpath?(expanded_cover_path, calibre_root) ->
        :ok

      true ->
        :error
    end
  end

  defp same_or_subpath?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end
