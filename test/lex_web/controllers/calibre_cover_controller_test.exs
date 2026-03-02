defmodule LexWeb.CalibreCoverControllerTest do
  use Lex.ConnCase, async: false

  setup do
    temp_dir =
      Path.join(System.tmp_dir!(), "calibre_cover_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(temp_dir)

    original_path = Application.fetch_env!(:lex, :calibre_library_path)
    Application.put_env(:lex, :calibre_library_path, temp_dir)

    on_exit(fn ->
      Application.put_env(:lex, :calibre_library_path, original_path)
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  test "serves cover image for valid token", %{conn: conn, temp_dir: temp_dir} do
    cover_path = Path.join(temp_dir, "cover.jpg")
    File.write!(cover_path, "fake-cover-bytes")

    token = Phoenix.Token.sign(LexWeb.Endpoint, "calibre_cover", cover_path)
    conn = get(conn, ~p"/calibre/covers/#{token}")

    assert conn.status == 200
    assert conn.resp_body == "fake-cover-bytes"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
  end

  test "returns 404 for invalid token", %{conn: conn} do
    conn = get(conn, "/calibre/covers/not-a-valid-token")

    assert conn.status == 404
  end

  test "returns 404 for signed path outside calibre root", %{conn: conn} do
    outside_path = Path.join(System.tmp_dir!(), "outside-cover.jpg")
    File.write!(outside_path, "outside")

    token = Phoenix.Token.sign(LexWeb.Endpoint, "calibre_cover", outside_path)
    conn = get(conn, ~p"/calibre/covers/#{token}")

    assert conn.status == 404

    File.rm(outside_path)
  end
end
