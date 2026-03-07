defmodule Lex.Vocab.StateTransitionsTest do
  @moduledoc """
  Comprehensive edge case tests for vocabulary state transitions.

  Tests all edge cases from SPEC §12:
  - Skip content behavior
  - Advance behavior
  - First encounter behavior
  - Backward navigation
  - Learning actions
  - State permanence
  """

  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Reader
  alias Lex.Reader.ReadingEvent
  alias Lex.Reader.UserSentenceState
  alias Lex.Repo
  alias Lex.Text.Lexeme
  alias Lex.Text.Sentence
  alias Lex.Text.Token
  alias Lex.Vocab.UserLexemeState

  # ============================================================================
  # Skip Content Behavior
  # ============================================================================

  describe "skip content behavior" do
    test "skip section does not mark words as known", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "Hola mundo.")
      sentence2 = create_sentence(section2, 1, "Start new chapter.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence1.id, lexeme.id, %{position: 1, surface: "Hola"})
      create_tokens_for_sentence(sentence2, ["Start", "new", "chapter", "."])

      # Mount (marks as seen)
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      state = Repo.one(UserLexemeState)
      assert state.status == "seen"

      # Skip section
      render_hook(view, :key_nav, %{"key" => "s"})

      # Should NOT be promoted to known
      state = Repo.one(UserLexemeState)
      assert state.status == "seen"
      assert state.known_at == nil
    end

    test "skip section does not mark sentences as read", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "End of chapter.")
      sentence2 = create_sentence(section2, 1, "Start.")
      create_tokens_for_sentence(sentence1, ["End", "of", "chapter", "."])
      create_tokens_for_sentence(sentence2, ["Start", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Skip section
      render_hook(view, :key_nav, %{"key" => "s"})

      # Should NOT have marked sentence as read
      count = Repo.aggregate(UserSentenceState, :count, :id)
      assert count == 0
    end

    test "skip to end of document works when at last section", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")

      sentence1 = create_sentence(section1, 1, "First.")
      _sentence2 = create_sentence(section1, 2, "Second.")
      last_sentence = create_sentence(section2, 1, "Last chapter.")

      create_tokens_for_sentence(sentence1, ["First", "."])
      create_tokens_for_sentence(last_sentence, ["Last", "chapter", "."])

      # Set position to first sentence
      {:ok, _} = Reader.set_position(user.id, document.id, section1.id, sentence1.id)

      # Mount at sentence1
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Skip to section 2
      render_hook(view, :key_nav, %{"key" => "s"})

      assert has_element?(view, ".reader-footer-section", section2.title)

      # Check we're at the last section by trying to skip again (should stay)
      _html2 = render_hook(view, :key_nav, %{"key" => "s"})
      # Should still show Chapter 2 (can't skip past last section)
      assert has_element?(view, ".reader-footer-section", section2.title)
    end
  end

  # ============================================================================
  # Advance Behavior
  # ============================================================================

  describe "advance behavior" do
    test "advancing sentence promotes non-learning words to known", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Primera frase.")
      sentence2 = create_sentence(section, 2, "Segunda frase.")
      lexeme = create_lexeme(%{lemma: "primera", normalized_lemma: "primera"})

      create_token(sentence1.id, lexeme.id, %{position: 1, surface: "Primera"})
      create_token(sentence2.id, nil, %{position: 1, surface: "Segunda", is_punctuation: false})

      # Mount and mark as seen
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      state = Repo.one(UserLexemeState)
      assert state.status == "seen"

      # Advance to next sentence
      render_hook(view, :key_nav, %{"key" => "j"})

      # Lexeme should now be known
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      assert state.known_at != nil
    end

    test "learning words stay learning on advance", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Hola mundo.")
      sentence2 = create_sentence(section, 2, "Adios mundo.")
      lexeme = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence1.id, lexeme.id, %{position: 2, surface: "mundo"})
      create_token(sentence2.id, lexeme.id, %{position: 2, surface: "mundo"})

      # Create a learning state
      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 3,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Verify learning state
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # Should still be learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"
      assert state.known_at == nil
    end

    test "known words stay known on advance", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Hola mundo.")
      sentence2 = create_sentence(section, 2, "Adios mundo.")
      lexeme = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence1.id, lexeme.id, %{position: 2, surface: "mundo"})
      create_token(sentence2.id, lexeme.id, %{position: 2, surface: "mundo"})

      # Create a known state
      known_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 10,
          known_at: known_at
        })
        |> Repo.insert()

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Verify known state
      state = Repo.one(UserLexemeState)
      assert state.status == "known"

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # Should still be known with same known_at
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      assert DateTime.compare(state.known_at, known_at) == :eq
    end

    test "punctuation tokens ignored for progression", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Hello, world!")
      sentence2 = create_sentence(section, 2, "Next.")
      lexeme = create_lexeme(%{lemma: "hello", normalized_lemma: "hello"})

      # Create tokens including punctuation
      create_token(sentence1.id, lexeme.id, %{position: 1, surface: "Hello"})
      # Punctuation token without lexeme
      create_token(sentence1.id, nil, %{position: 2, surface: ",", is_punctuation: true})
      create_token(sentence1.id, nil, %{position: 3, surface: "world", is_punctuation: false})
      create_token(sentence1.id, nil, %{position: 4, surface: "!", is_punctuation: true})
      create_tokens_for_sentence(sentence2, ["Next", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Should have only one lexeme state (punctuation ignored)
      states = Repo.all(UserLexemeState)
      assert length(states) == 1
      assert hd(states).lexeme_id == lexeme.id

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # Punctuation tokens should not have created any lexeme states
      states = Repo.all(UserLexemeState)
      assert length(states) == 1
    end

    test "sentence becomes read only on normal advance", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First sentence.")
      sentence2 = create_sentence(section, 2, "Second sentence.")
      create_tokens_for_sentence(sentence1, ["First", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "sentence", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # No sentence state yet (entering doesn't mark as read)
      assert Repo.aggregate(UserSentenceState, :count, :id) == 0

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # First sentence should now be marked as read
      sentence_state = Repo.one(UserSentenceState)
      assert sentence_state.sentence_id == sentence1.id
      assert sentence_state.status == "read"
      assert sentence_state.read_at != nil
    end
  end

  # ============================================================================
  # First Encounter
  # ============================================================================

  describe "first encounter" do
    test "first view marks all non-punct lexemes as seen", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola mundo.")
      lexeme1 = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme2 = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence.id, lexeme1.id, %{position: 1, surface: "Hola"})
      create_token(sentence.id, lexeme2.id, %{position: 2, surface: "mundo"})
      create_token(sentence.id, nil, %{position: 3, surface: ".", is_punctuation: true})

      # No states should exist before mounting
      assert Repo.aggregate(UserLexemeState, :count, :id) == 0

      # Mount the reader
      {:ok, _view, _html} = live(conn, "/read/#{document.id}")

      # Both lexemes should be marked as seen (not punctuation)
      states = Repo.all(UserLexemeState)
      assert length(states) == 2

      lexeme_ids = Enum.map(states, & &1.lexeme_id)
      assert lexeme1.id in lexeme_ids
      assert lexeme2.id in lexeme_ids

      assert Enum.all?(states, fn s -> s.status == "seen" end)
      assert Enum.all?(states, fn s -> s.seen_count == 1 end)
    end

    test "repeated tokens in one sentence don't create duplicate state rows", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Buffalo buffalo buffalo.")
      lexeme = create_lexeme(%{lemma: "buffalo", normalized_lemma: "buffalo"})

      # Create multiple tokens for the same lexeme
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Buffalo"})
      create_token(sentence.id, lexeme.id, %{position: 2, surface: "buffalo"})
      create_token(sentence.id, lexeme.id, %{position: 3, surface: "buffalo"})
      create_token(sentence.id, nil, %{position: 4, surface: ".", is_punctuation: true})

      # Mount the reader
      {:ok, _view, _html} = live(conn, "/read/#{document.id}")

      # Should have only ONE state row despite 3 tokens
      states = Repo.all(UserLexemeState)
      assert length(states) == 1

      state = hd(states)
      assert state.lexeme_id == lexeme.id
      assert state.status == "seen"
      assert state.seen_count == 1
    end

    test "second view of same sentence doesn't increment seen_count twice", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Hello world.")
      sentence2 = create_sentence(section, 2, "Next.")
      lexeme1 = create_lexeme(%{lemma: "hello", normalized_lemma: "hello"})
      lexeme2 = create_lexeme(%{lemma: "world", normalized_lemma: "world"})

      # Create tokens individually to avoid position conflicts
      create_token(sentence1.id, lexeme1.id, %{position: 1, surface: "Hello"})
      create_token(sentence1.id, lexeme2.id, %{position: 2, surface: "world"})
      create_token(sentence1.id, nil, %{position: 3, surface: ".", is_punctuation: true})

      # Sentence 2 tokens
      create_tokens_for_sentence(sentence2, ["Next", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # First view - seen_count should be set
      state = Repo.get_by(UserLexemeState, lexeme_id: lexeme1.id)
      initial_count = state.seen_count

      # Advance to next sentence (marks as known)
      render_hook(view, :key_nav, %{"key" => "j"})

      # Go back to first sentence
      render_hook(view, :key_nav, %{"key" => "k"})

      # seen_count should NOT have incremented when going backward
      state = Repo.get_by(UserLexemeState, lexeme_id: lexeme1.id)
      assert state.seen_count == initial_count
    end
  end

  # ============================================================================
  # Backward Navigation
  # ============================================================================

  describe "backward navigation" do
    test "going backward never changes lexeme state", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Primera.")
      sentence2 = create_sentence(section, 2, "Segunda.")
      lexeme = create_lexeme(%{lemma: "primera", normalized_lemma: "primera"})

      create_token(sentence1.id, lexeme.id, %{position: 1, surface: "Primera"})
      create_tokens_for_sentence(sentence2, ["Segunda", "."])

      # Mount and advance
      {:ok, view, _html} = live(conn, "/read/#{document.id}")
      render_hook(view, :key_nav, %{"key" => "j"})

      # First sentence words are now known
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      known_at = state.known_at

      # Go backward
      render_hook(view, :key_nav, %{"key" => "k"})

      # Should stay known (not changed to seen)
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      assert DateTime.compare(state.known_at, known_at) == :eq
    end

    test "going backward never marks sentence read", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First.")
      sentence2 = create_sentence(section, 2, "Second.")
      create_tokens_for_sentence(sentence1, ["First", "."])
      create_tokens_for_sentence(sentence2, ["Second", "."])

      # Mount, advance (marks first as read), then go back
      {:ok, view, _html} = live(conn, "/read/#{document.id}")
      render_hook(view, :key_nav, %{"key" => "j"})

      # One sentence should be marked as read
      assert Repo.aggregate(UserSentenceState, :count, :id) == 1

      # Go backward (should not create new read marks)
      render_hook(view, :key_nav, %{"key" => "k"})

      # Should still only have one sentence marked as read
      assert Repo.aggregate(UserSentenceState, :count, :id) == 1
    end
  end

  # ============================================================================
  # Learning Actions
  # ============================================================================

  describe "learning actions" do
    test "toggle learning creates state if none exists", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola mundo.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})
      create_token(sentence.id, nil, %{position: 2, surface: "mundo", is_punctuation: false})

      # Before mounting, no state should exist
      assert Repo.aggregate(UserLexemeState, :count, :id) == 0

      # Mount (this marks lexemes as seen)
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # After mount, state should exist as "seen"
      state = Repo.one(UserLexemeState)
      assert state.status == "seen"

      # Now test that toggle learning can change from seen -> learning
      # Focus token and toggle learning
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "l"})

      # State should now be learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"
      assert state.learning_since != nil
    end

    test "unmarking learning reverts to seen", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola mundo.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})

      # Create existing learning state
      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 5,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus and toggle twice (learning -> seen)
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "l"})

      # Should be back to seen
      state = Repo.one(UserLexemeState)
      assert state.status == "seen"
      assert state.learning_since == nil
    end

    test "known words cannot be unmarked", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})

      # Create known state
      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 10,
          known_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus and try to toggle
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "l"})

      # Should still be known
      state = Repo.one(UserLexemeState)
      assert state.status == "known"

      # Should not have logged any learning events
      count =
        ReadingEvent
        |> where([e], e.event_type in ["mark_learning", "unmark_learning"])
        |> Repo.aggregate(:count, :id)

      assert count == 0
    end

    test "LLM help marks word as learning", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola mundo.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})
      create_token(sentence.id, nil, %{position: 2, surface: "mundo", is_punctuation: false})

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # State should be seen after mount
      state = Repo.one(UserLexemeState)
      assert state.status == "seen"

      # Focus token and request LLM help (space key)
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "space"})

      # Word should now be learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"
      assert state.learning_since != nil
    end
  end

  # ============================================================================
  # State Permanence
  # ============================================================================

  describe "state permanence" do
    test "known words never demote automatically", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Hola mundo.")
      sentence2 = create_sentence(section, 2, "Adios mundo.")
      lexeme = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence1.id, lexeme.id, %{position: 2, surface: "mundo"})
      create_token(sentence2.id, lexeme.id, %{position: 2, surface: "mundo"})

      # Create known state
      known_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 10,
          known_at: known_at
        })
        |> Repo.insert()

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Go forward and back multiple times
      render_hook(view, :key_nav, %{"key" => "j"})
      render_hook(view, :key_nav, %{"key" => "k"})
      render_hook(view, :key_nav, %{"key" => "j"})
      render_hook(view, :key_nav, %{"key" => "k"})

      # Should still be known
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      assert DateTime.compare(state.known_at, known_at) == :eq
    end

    test "learning only changes via explicit action", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Hola mundo.")
      sentence2 = create_sentence(section, 2, "Adios mundo.")
      lexeme = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence1.id, lexeme.id, %{position: 2, surface: "mundo"})
      create_token(sentence2.id, lexeme.id, %{position: 2, surface: "mundo"})

      # Create learning state
      learning_since = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 5,
          learning_since: learning_since
        })
        |> Repo.insert()

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Navigate around without explicit action
      render_hook(view, :key_nav, %{"key" => "j"})
      render_hook(view, :key_nav, %{"key" => "k"})
      render_hook(view, :key_nav, %{"key" => "j"})

      # Should still be learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"
      assert DateTime.compare(state.learning_since, learning_since) == :eq
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Test User",
      email: "test#{unique_id}@example.com",
      primary_language: "en"
    }

    attrs = Map.merge(default_attrs, attrs)

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!()
  end

  defp create_ready_document(user) do
    %Document{}
    |> Document.changeset(%{
      title: "Test Document",
      author: "Test Author",
      language: "es",
      status: "ready",
      source_file: "test.epub",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp create_section(document, position \\ 1, title \\ "Test Section") do
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

  defp create_lexeme(attrs) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      language: "es",
      lemma: "test#{unique_id}",
      normalized_lemma: "test#{unique_id}",
      pos: "NOUN"
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lexeme{}
    |> Lexeme.changeset(attrs)
    |> Repo.insert!()
  end

  defp create_token(sentence_id, lexeme_id, attrs) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      position: 1,
      surface: "test",
      normalized_surface: "test",
      lemma: "test#{unique_id}",
      pos: "NOUN",
      is_punctuation: false,
      char_start: 0,
      char_end: 4,
      sentence_id: sentence_id,
      lexeme_id: lexeme_id
    }

    attrs = Map.merge(default_attrs, attrs)

    %Token{}
    |> Token.changeset(attrs)
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
