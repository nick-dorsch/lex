defmodule LexWeb.ReaderLive.KeyboardTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Repo
  alias Lex.Text.Sentence
  alias Lex.Text.Token

  describe "keyboard navigation" do
    test "handles key_nav event for 'j' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for 'j' key
      assert render_hook(view, :key_nav, %{"key" => "j"})
    end

    test "handles key_nav event for 'k' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for 'k' key
      assert render_hook(view, :key_nav, %{"key" => "k"})
    end

    test "handles key_nav event for 'w' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for 'w' key
      assert render_hook(view, :key_nav, %{"key" => "w"})
    end

    test "handles key_nav event for 'b' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for 'b' key
      assert render_hook(view, :key_nav, %{"key" => "b"})
    end

    test "handles key_nav event for 'space' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for 'space' key
      assert render_hook(view, :key_nav, %{"key" => "space"})
    end

    test "ignores unknown keys in key_nav event", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for unknown key
      assert render_hook(view, :key_nav, %{"key" => "x"})
    end
  end

  describe "token navigation with w/b keys" do
    test "'w' key focuses first token when no token is focused", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Initially no token should have focus ring
      html = render(view)
      refute html =~ "ring-2 ring-indigo-500"

      # Press 'w' to focus first token
      html = render_hook(view, :key_nav, %{"key" => "w"})
      assert html =~ "ring-2 ring-indigo-500"
      assert html =~ "First"
    end

    test "'w' key moves focus to next token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus first token
      render_hook(view, :key_nav, %{"key" => "w"})

      # Move to second token
      html = render_hook(view, :key_nav, %{"key" => "w"})
      assert html =~ "second"
    end

    test "'w' key wraps to first token when at last token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second.")
      create_tokens_for_sentence(sentence, ["First", "second", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus last token (3rd token - "second")
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "w"})

      # Wrap to first token
      html = render_hook(view, :key_nav, %{"key" => "w"})
      assert html =~ "First"
    end

    test "'b' key focuses last token when no token is focused", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Press 'b' to focus last token
      html = render_hook(view, :key_nav, %{"key" => "b"})
      assert html =~ "ring-2 ring-indigo-500"
      assert html =~ "third"
    end

    test "'b' key moves focus to previous token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus last token
      render_hook(view, :key_nav, %{"key" => "b"})

      # Move to previous token
      html = render_hook(view, :key_nav, %{"key" => "b"})
      assert html =~ "second"
    end

    test "'b' key wraps to last token when at first token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus first token
      render_hook(view, :key_nav, %{"key" => "w"})

      # Wrap to last token
      html = render_hook(view, :key_nav, %{"key" => "b"})
      assert html =~ "third"
    end

    test "focus resets when navigating to next sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First sentence.")
      sentence2 = create_sentence(section, 2, "Second sentence.")
      create_tokens_for_sentence(sentence1, ["First", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token in first sentence
      html = render_hook(view, :key_nav, %{"key" => "w"})
      assert html =~ "ring-2 ring-indigo-500"

      # Navigate to next sentence
      html = render_hook(view, :key_nav, %{"key" => "j"})

      # Focus should be reset (no ring)
      refute html =~ "ring-2 ring-indigo-500"
    end

    test "focus resets when navigating to previous sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First sentence.")
      sentence2 = create_sentence(section, 2, "Second sentence.")
      create_tokens_for_sentence(sentence1, ["First", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Navigate to second sentence
      render_hook(view, :key_nav, %{"key" => "j"})

      # Focus a token in second sentence
      html = render_hook(view, :key_nav, %{"key" => "w"})
      assert html =~ "ring-2 ring-indigo-500"

      # Navigate back to first sentence
      html = render_hook(view, :key_nav, %{"key" => "k"})

      # Focus should be reset (no ring)
      refute html =~ "ring-2 ring-indigo-500"
    end
  end

  describe "token click to focus" do
    test "clicking a token sets focus to that token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Click on the second token (index 2, since Enum.with_index starts at 1)
      html = render_click(view, :focus_token, %{"token_index" => "2"})

      # Should show focus indicator
      assert html =~ "ring-2 ring-indigo-500"
      assert html =~ "second"
    end
  end

  # Helper functions for creating test data

  defp create_user do
    %User{}
    |> User.changeset(%{
      name: "Test User",
      email: "test#{System.unique_integer()}_#{:erlang.monotonic_time()}@example.com",
      primary_language: "en"
    })
    |> Repo.insert!()
  end

  defp create_ready_document(user) do
    %Document{}
    |> Document.changeset(%{
      title: "Test Document",
      author: "Test Author",
      language: "en",
      status: "ready",
      source_file: "test.epub",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp create_section(document, title \\ "Test Section") do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: 1,
      title: title
    })
    |> Repo.insert!()
  end

  defp create_sentence(section, position, text) do
    %Sentence{}
    |> Sentence.changeset(%{
      section_id: section.id,
      position: position,
      text: text,
      char_start: 0,
      char_end: String.length(text)
    })
    |> Repo.insert!()
  end

  defp create_tokens_for_sentence(sentence, words) do
    words
    |> Enum.with_index(1)
    |> Enum.map(fn {word, position} ->
      %Token{}
      |> Token.changeset(%{
        sentence_id: sentence.id,
        position: position,
        surface: word,
        normalized_surface: String.downcase(word),
        lemma: String.downcase(word),
        pos: "WORD",
        is_punctuation: word in [".", ",", "!", "?", ";", ":"],
        char_start: 0,
        char_end: String.length(word)
      })
      |> Repo.insert!()
    end)
  end
end
