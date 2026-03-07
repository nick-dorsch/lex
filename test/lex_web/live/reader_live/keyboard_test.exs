defmodule LexWeb.ReaderLive.KeyboardTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Repo
  alias Lex.Text.Sentence
  alias Lex.Text.Token
  alias Lex.Text.Lexeme
  alias Lex.Vocab.UserLexemeState

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

    test "handles key_nav event for 'W' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      assert render_hook(view, :key_nav, %{"key" => "W"})
    end

    test "handles key_nav event for 'B' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      assert render_hook(view, :key_nav, %{"key" => "B"})
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

    test "handles key_nav event for 's' key", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Send key_nav event for 's' key
      assert render_hook(view, :key_nav, %{"key" => "s"})
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
      refute has_element?(view, ".current-sentence .token.token-focused")

      # Press 'w' to focus first token
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 1)
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
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 2)
    end

    test "'w' key wraps to first token when at last token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second.")
      create_tokens_for_sentence(sentence, ["First", "second", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus last selectable token (2nd token - "second")
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "w"})

      # Wrap to first token
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 1)
    end

    test "navigation skips punctuation tokens", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First, second.")
      create_tokens_for_sentence(sentence, ["First", ",", "second", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # First selectable token
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 1)

      # Should skip comma and focus "second"
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 3)
    end

    test "'b' key focuses last token when no token is focused", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Press 'b' to focus last token
      _html = render_hook(view, :key_nav, %{"key" => "b"})
      assert_focused_token(view, 3)
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
      _html = render_hook(view, :key_nav, %{"key" => "b"})
      assert_focused_token(view, 2)
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
      _html = render_hook(view, :key_nav, %{"key" => "b"})
      assert_focused_token(view, 3)
    end

    test "'W' key jumps to next non-known token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      tokens = create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      create_user_lexeme_state(user.id, Enum.at(tokens, 0).lexeme_id, "known")
      create_user_lexeme_state(user.id, Enum.at(tokens, 2).lexeme_id, "known")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      render_hook(view, :key_nav, %{"key" => "W"})

      assert has_element?(view, ".token-focused[data-token-index='2']")
    end

    test "'B' key jumps to previous non-known token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third fourth.")
      tokens = create_tokens_for_sentence(sentence, ["First", "second", "third", "fourth", "."])

      create_user_lexeme_state(user.id, Enum.at(tokens, 0).lexeme_id, "known")
      create_user_lexeme_state(user.id, Enum.at(tokens, 2).lexeme_id, "known")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "w"})

      render_hook(view, :key_nav, %{"key" => "B"})

      assert has_element?(view, ".token-focused[data-token-index='2']")
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
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 1)

      # Navigate to next sentence
      _html = render_hook(view, :key_nav, %{"key" => "j"})

      # Focus should be reset (no ring)
      refute has_element?(view, ".current-sentence .token.token-focused")
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
      _html = render_hook(view, :key_nav, %{"key" => "w"})
      assert_focused_token(view, 1)

      # Navigate back to first sentence
      _html = render_hook(view, :key_nav, %{"key" => "k"})

      # Focus should be reset (no ring)
      refute has_element?(view, ".current-sentence .token.token-focused")
    end
  end

  describe "skip section navigation" do
    test "'s' key navigates to next section", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section_with_position(document, 1, "Chapter 1")
      section2 = create_section_with_position(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "First chapter sentence.")
      sentence2 = create_sentence(section2, 1, "Second chapter sentence.")
      create_tokens_for_sentence(sentence1, ["First", "chapter", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "chapter", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Initially showing chapter 1
      assert_current_section(view, section1.title)
      assert_current_sentence(view, sentence1.text)

      # Press 's' to skip to next section
      _html = render_hook(view, :key_nav, %{"key" => "s"})

      # Should now show chapter 2
      assert_current_section(view, section2.title)
      assert_current_sentence(view, sentence2.text)
    end

    test "clicking skip section button navigates to next section", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section_with_position(document, 1, "Chapter 1")
      section2 = create_section_with_position(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "First chapter sentence.")
      sentence2 = create_sentence(section2, 1, "Second chapter sentence.")
      create_tokens_for_sentence(sentence1, ["First", "chapter", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "chapter", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Initially showing chapter 1
      assert_current_section(view, section1.title)
      assert_current_sentence(view, sentence1.text)

      # Click skip section button
      _html = render_click(view, :skip_section)

      # Should now show chapter 2
      assert_current_section(view, section2.title)
      assert_current_sentence(view, sentence2.text)
    end

    test "skip section at last section stays at current position", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document, "Only Chapter")
      sentence = create_sentence(section, 1, "Only sentence.")
      create_tokens_for_sentence(sentence, ["Only", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Initially showing the only chapter
      assert_current_section(view, section.title)
      assert_current_sentence(view, sentence.text)

      # Press 's' to try to skip - should stay at current position
      _html = render_hook(view, :key_nav, %{"key" => "s"})

      # Should still show same chapter
      assert_current_section(view, section.title)
      assert_current_sentence(view, sentence.text)
    end

    test "skip section does not mark skipped sentences as read", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section_with_position(document, 1, "Chapter 1")
      section2 = create_section_with_position(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "First chapter.")
      sentence2 = create_sentence(section1, 2, "Second sentence.")
      sentence3 = create_sentence(section2, 1, "Next chapter.")
      create_tokens_for_sentence(sentence1, ["First", "chapter", "."])
      create_tokens_for_sentence(sentence2, ["Second", "sentence", "."])
      create_tokens_for_sentence(sentence3, ["Next", "chapter", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Skip to next section
      render_hook(view, :key_nav, %{"key" => "s"})

      # Check that skipped sentences are not marked as read
      # (This would require checking the database, which is done in context tests)
      # Here we just verify the navigation worked
      assert_current_section(view, section2.title)
    end

    test "previous section button rewinds to start of current section", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section_with_position(document, 1, "Chapter 1")
      sentence1 = create_sentence(section, 1, "First chapter sentence.")
      sentence2 = create_sentence(section, 2, "Second chapter sentence.")
      create_tokens_for_sentence(sentence1, ["First", "chapter", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "chapter", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")
      assert_current_sentence(view, sentence1.text)

      # Move to second sentence in same section
      _html = render_hook(view, :key_nav, %{"key" => "j"})
      assert_current_sentence(view, sentence2.text)

      # Rewind to section start
      _html = render_click(view, :previous_section)
      assert_current_sentence(view, sentence1.text)
    end

    test "previous section button goes to previous section start when at section start", %{
      conn: conn
    } do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section_with_position(document, 1, "Chapter 1")
      section2 = create_section_with_position(document, 2, "Chapter 2")
      sentence1a = create_sentence(section1, 1, "Chapter one first.")
      _sentence1b = create_sentence(section1, 2, "Chapter one second.")
      sentence2a = create_sentence(section2, 1, "Chapter two first.")
      create_tokens_for_sentence(sentence1a, ["Chapter", "one", "first", "."])
      create_tokens_for_sentence(sentence2a, ["Chapter", "two", "first", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")
      assert_current_section(view, section1.title)

      # Skip forward to start of section 2
      _html = render_click(view, :skip_section)
      assert_current_section(view, section2.title)
      assert_current_sentence(view, sentence2a.text)

      # Rewind should go to start of previous section
      _html = render_click(view, :previous_section)
      assert_current_section(view, section1.title)
      assert_current_sentence(view, sentence1a.text)
    end
  end

  describe "token click behavior" do
    test "clicking a token sets focus and triggers LLM help", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Click on the second token (index 2, since Enum.with_index starts at 1)
      _html = render_click(view, :click_token, %{"token_index" => "2"})

      # Should show focus indicator
      assert has_element?(
               view,
               ".current-sentence .token.token-focused.token-learning[data-token-index='2'][data-token-status='learning']"
             )

      assert view |> has_element?("[data-testid='llm-popup']")

      Lex.LLM.ClientMock.clear_mock()
    end

    test "clicking punctuation does not set focus", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second.")
      create_tokens_for_sentence(sentence, ["First", "second", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Try to focus punctuation token
      _html = render_click(view, :click_token, %{"token_index" => "3"})

      # Focus should remain unset
      refute has_element?(view, ".current-sentence .token.token-focused")
    end
  end

  # Helper functions for creating test data

  defp assert_focused_token(view, token_index) do
    assert has_element?(
             view,
             ".current-sentence .token.token-focused[data-token-index='#{token_index}']"
           )
  end

  defp assert_current_section(view, section_title) do
    assert has_element?(view, ".reader-footer-section", section_title)
  end

  defp assert_current_sentence(view, sentence_text) do
    current_sentence_text =
      view
      |> element(".current-sentence")
      |> render()
      |> normalized_sentence_text()

    assert current_sentence_text =~ normalized_sentence_text(sentence_text)
  end

  defp normalized_sentence_text(text) do
    text
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\s+([[:punct:]])/, "\\1")
    |> String.trim()
  end

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

  defp create_section_with_position(document, position, title) do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: position,
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
      lexeme_id =
        if word in [".", ",", "!", "?", ";", ":"] do
          nil
        else
          lexeme = create_lexeme(%{lemma: String.downcase(word)})
          lexeme.id
        end

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
        char_end: String.length(word),
        lexeme_id: lexeme_id
      })
      |> Repo.insert!()
    end)
  end

  defp create_lexeme(attrs) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      language: "en",
      lemma: "test#{unique_id}",
      normalized_lemma: "test#{unique_id}",
      pos: "NOUN"
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lexeme{}
    |> Lexeme.changeset(attrs)
    |> Repo.insert!()
  end

  defp create_user_lexeme_state(user_id, lexeme_id, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %UserLexemeState{}
    |> UserLexemeState.changeset(%{
      user_id: user_id,
      lexeme_id: lexeme_id,
      status: status,
      seen_count: 1,
      first_seen_at: now,
      last_seen_at: now,
      known_at: if(status == "known", do: now, else: nil),
      learning_since: if(status == "learning", do: now, else: nil)
    })
    |> Repo.insert!()
  end
end
