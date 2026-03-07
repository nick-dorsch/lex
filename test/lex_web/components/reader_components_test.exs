defmodule LexWeb.ReaderComponentsTest do
  use Lex.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LexWeb.ReaderComponents

  describe "token/1" do
    test "renders token surface and token id" do
      token = %{id: 42, surface: "data-test"}
      html = render_component(&token/1, token: token, status: :new, focused: false)

      span = html |> Floki.parse_fragment!() |> Floki.find("span[data-token-id='42']")
      assert span != []
      assert Floki.text(span) =~ "data-test"
    end

    test "supports all statuses" do
      for status <- [:new, :seen, :learning, :known] do
        token = %{id: System.unique_integer([:positive]), surface: Atom.to_string(status)}

        html = render_component(&token/1, token: token, status: status, focused: false)

        span =
          html
          |> Floki.parse_fragment!()
          |> Floki.find("span[data-token-id='#{token.id}']")

        assert span != []
        assert Floki.text(span) =~ token.surface
      end
    end

    test "adds focus marker when focused" do
      token = %{id: 99, surface: "focused"}
      focused_html = render_component(&token/1, token: token, status: :new, focused: true)
      unfocused_html = render_component(&token/1, token: token, status: :new, focused: false)

      assert focused_html =~ "ring-2"
      refute unfocused_html =~ "ring-2"
    end
  end
end
