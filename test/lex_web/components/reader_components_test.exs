defmodule LexWeb.ReaderComponentsTest do
  use Lex.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LexWeb.ReaderComponents

  describe "token/1" do
    test "renders new status with amber background" do
      token = %{id: 1, surface: "hello"}
      html = render_component(&token/1, token: token, status: :new, focused: false)

      assert html =~ "hello"
      assert html =~ "bg-amber-900/60"
      assert html =~ "rounded"
      refute html =~ "ring-2"
    end

    test "renders seen status with gray dotted border" do
      token = %{id: 2, surface: "world"}
      html = render_component(&token/1, token: token, status: :seen, focused: false)

      assert html =~ "world"
      assert html =~ "border-slate-500"
      assert html =~ "border-dashed"
      refute html =~ "ring-2"
    end

    test "renders learning status with blue background" do
      token = %{id: 3, surface: "test"}
      html = render_component(&token/1, token: token, status: :learning, focused: false)

      assert html =~ "test"
      assert html =~ "bg-blue-900/60"
      assert html =~ "rounded"
      refute html =~ "ring-2"
    end

    test "renders known status with no special styling" do
      token = %{id: 4, surface: "known"}
      html = render_component(&token/1, token: token, status: :known, focused: false)

      assert html =~ "known"
      refute html =~ "bg-amber-900/60"
      refute html =~ "bg-blue-900/60"
      refute html =~ "border-slate-500"
      refute html =~ "ring-2"
    end

    test "adds focus ring when focused" do
      token = %{id: 5, surface: "focused"}
      html = render_component(&token/1, token: token, status: :new, focused: true)

      assert html =~ "focused"
      assert html =~ "bg-amber-900/60"
      assert html =~ "ring-2"
      assert html =~ "ring-indigo-500"
    end

    test "focus ring works with seen status" do
      token = %{id: 6, surface: "seen-focused"}
      html = render_component(&token/1, token: token, status: :seen, focused: true)

      assert html =~ "seen-focused"
      assert html =~ "border-dashed"
      assert html =~ "ring-2"
      assert html =~ "ring-indigo-500"
    end

    test "focus ring works with learning status" do
      token = %{id: 7, surface: "learning-focused"}
      html = render_component(&token/1, token: token, status: :learning, focused: true)

      assert html =~ "learning-focused"
      assert html =~ "bg-blue-900/60"
      assert html =~ "ring-2"
      assert html =~ "ring-indigo-500"
    end

    test "focus ring works with known status" do
      token = %{id: 8, surface: "known-focused"}
      html = render_component(&token/1, token: token, status: :known, focused: true)

      assert html =~ "known-focused"
      assert html =~ "ring-2"
      assert html =~ "ring-indigo-500"
    end

    test "includes token id in data attribute" do
      token = %{id: 42, surface: "data-test"}
      html = render_component(&token/1, token: token, status: :new, focused: false)

      assert html =~ ~s(data-token-id="42")
    end
  end
end
