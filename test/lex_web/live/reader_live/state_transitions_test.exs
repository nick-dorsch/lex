defmodule LexWeb.ReaderLive.StateTransitionsTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Text.Token
  alias Lex.Text.Lexeme
  alias Lex.Vocab.UserLexemeState
  alias Lex.Reader.UserSentenceState
  alias Lex.Reader.ReadingEvent
  alias Lex.Reader

  describe "state transitions on sentence display (mount)" do
    test "marks lexemes as seen when mounting the reader", %{conn: conn} do
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

      # Lexemes should now be marked as seen
      states = Repo.all(UserLexemeState)
      assert length(states) == 2
      assert Enum.all?(states, fn s -> s.status == "seen" end)
      assert Enum.all?(states, fn s -> s.user_id == user.id end)
    end

    test "logs enter_sentence event when mounting", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Test sentence.")
      create_tokens_for_sentence(sentence, ["Test", "sentence", "."])

      # Mount the reader (LiveView mounts twice in tests: static + connected)
      {:ok, _view, _html} = live(conn, "/read/#{document.id}")

      # Should have logged at least one enter_sentence event
      events =
        ReadingEvent
        |> where([e], e.user_id == ^user.id and e.event_type == "enter_sentence")
        |> Repo.all()

      assert length(events) >= 1
      event = hd(events)
      assert event.document_id == document.id
      assert event.sentence_id == sentence.id
    end
  end

  describe "state transitions on advance (j key)" do
    test "promotes seen words to known when advancing", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "Primera frase.")
      sentence2 = create_sentence(section, 2, "Segunda frase.")
      lexeme = create_lexeme(%{lemma: "primera", normalized_lemma: "primera"})

      create_token(sentence1.id, lexeme.id, %{position: 1, surface: "Primera"})
      create_token(sentence1.id, nil, %{position: 2, surface: "frase", is_punctuation: false})
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

    test "marks sentence as read when advancing", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First sentence.")
      sentence2 = create_sentence(section, 2, "Second sentence.")
      create_tokens_for_sentence(sentence1, ["First", "sentence", "."])
      create_tokens_for_sentence(sentence2, ["Second", "sentence", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # No sentence state yet
      assert Repo.aggregate(UserSentenceState, :count, :id) == 0

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # First sentence should be marked as read
      sentence_state = Repo.one(UserSentenceState)
      assert sentence_state.user_id == user.id
      assert sentence_state.sentence_id == sentence1.id
      assert sentence_state.status == "read"
      assert sentence_state.read_at != nil
    end

    test "logs advance_sentence event with correct metadata", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First.")
      sentence2 = create_sentence(section, 2, "Second.")
      create_tokens_for_sentence(sentence1, ["First", "."])
      create_tokens_for_sentence(sentence2, ["Second", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Clear initial enter_sentence event
      Repo.delete_all(ReadingEvent)

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # Should have logged advance_sentence event
      events =
        ReadingEvent
        |> where([e], e.user_id == ^user.id and e.event_type == "advance_sentence")
        |> Repo.all()

      assert length(events) == 1
      event = hd(events)
      assert event.document_id == document.id

      payload = ReadingEvent.decode_payload(event)
      assert payload["from_sentence_id"] == sentence1.id
      assert payload["to_sentence_id"] == sentence2.id
      assert payload["from_section_id"] == section.id
      assert payload["to_section_id"] == section.id
    end

    test "marks lexemes as seen for new sentence after advance", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence1 = create_sentence(section, 1, "First.")
      sentence2 = create_sentence(section, 2, "Second word.")
      lexeme = create_lexeme(%{lemma: "word", normalized_lemma: "word"})

      create_tokens_for_sentence(sentence1, ["First", "."])
      create_token(sentence2.id, lexeme.id, %{position: 2, surface: "word"})

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Only first sentence tokens marked
      assert Repo.aggregate(UserLexemeState, :count, :id) == 0

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # New sentence lexeme should be marked as seen
      state = Repo.one(UserLexemeState)
      assert state.lexeme_id == lexeme.id
      assert state.status == "seen"
    end

    test "preserves learning words when advancing", %{conn: conn} do
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

      # Advance
      render_hook(view, :key_nav, %{"key" => "j"})

      # Should still be learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"
    end

    test "does nothing at end of document", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Only sentence.")
      create_tokens_for_sentence(sentence, ["Only", "sentence", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Clear events
      Repo.delete_all(ReadingEvent)

      # Try to advance (should fail silently)
      _html = render_hook(view, :key_nav, %{"key" => "j"})

      # Should still show the same sentence
      assert has_element?(view, ".reader-footer-section", section.title)

      # Should not have logged an advance event
      count =
        ReadingEvent
        |> where([e], e.event_type == "advance_sentence")
        |> Repo.aggregate(:count, :id)

      assert count == 0
    end
  end

  describe "state transitions on backward (k key)" do
    test "does not promote words when going backward", %{conn: conn} do
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

      # Go backward
      render_hook(view, :key_nav, %{"key" => "k"})

      # Should stay known (not changed)
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
    end

    test "does not mark sentence as read when going backward", %{conn: conn} do
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

      # Go backward
      render_hook(view, :key_nav, %{"key" => "k"})

      # Should still only have one sentence marked as read
      assert Repo.aggregate(UserSentenceState, :count, :id) == 1
    end
  end

  describe "state transitions on skip section (s key)" do
    test "logs skip_range event when skipping section", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "End of chapter 1.")
      sentence2 = create_sentence(section2, 1, "Start of chapter 2.")
      create_tokens_for_sentence(sentence1, ["End", "of", "chapter", "1", "."])
      create_tokens_for_sentence(sentence2, ["Start", "of", "chapter", "2", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Clear events
      Repo.delete_all(ReadingEvent)

      # Skip section
      render_hook(view, :key_nav, %{"key" => "s"})

      # Should have logged skip_range event
      events =
        ReadingEvent
        |> where([e], e.user_id == ^user.id and e.event_type == "skip_range")
        |> Repo.all()

      assert length(events) == 1
      event = hd(events)
      assert event.document_id == document.id

      payload = ReadingEvent.decode_payload(event)
      assert payload["from_section_id"] == section1.id
      assert payload["to_section_id"] == section2.id
      assert payload["from_sentence_id"] == sentence1.id
      assert payload["to_sentence_id"] == sentence2.id
      assert payload["skipped_sentences"] == 0
    end

    test "marks lexemes as seen for new sentence after skip", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "End.")
      sentence2 = create_sentence(section2, 1, "New chapter start.")
      lexeme = create_lexeme(%{lemma: "chapter", normalized_lemma: "chapter"})

      create_tokens_for_sentence(sentence1, ["End", "."])
      create_token(sentence2.id, lexeme.id, %{position: 2, surface: "chapter"})

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Skip section
      render_hook(view, :key_nav, %{"key" => "s"})

      # New sentence lexeme should be marked as seen
      state = Repo.one(UserLexemeState)
      assert state.lexeme_id == lexeme.id
      assert state.status == "seen"
    end

    test "does NOT promote words when skipping", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")
      sentence1 = create_sentence(section1, 1, "Hola mundo.")
      sentence2 = create_sentence(section2, 1, "Start.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence1.id, lexeme.id, %{position: 1, surface: "Hola"})
      create_tokens_for_sentence(sentence2, ["Start", "."])

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

    test "does NOT mark sentence as read when skipping", %{conn: conn} do
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

    test "counts skipped sentences correctly", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section1 = create_section(document, 1, "Chapter 1")
      section2 = create_section(document, 2, "Chapter 2")
      section3 = create_section(document, 3, "Chapter 3")

      # Section 1: 2 sentences
      sentence1 = create_sentence(section1, 1, "First.")
      _sentence2 = create_sentence(section1, 2, "Second.")

      # Section 2: 3 sentences
      sentence3 = create_sentence(section2, 1, "Third.")
      _sentence4 = create_sentence(section2, 2, "Fourth.")
      _sentence5 = create_sentence(section2, 3, "Fifth.")

      # Section 3: 1 sentence
      _sentence6 = create_sentence(section3, 1, "Sixth.")

      create_tokens_for_sentence(sentence1, ["First", "."])
      create_tokens_for_sentence(sentence3, ["Third", "."])

      # Set position to first sentence of section 1
      {:ok, _} =
        Reader.set_position(user.id, document.id, section1.id, sentence1.id)

      # Mount at sentence1
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Clear events
      Repo.delete_all(ReadingEvent)

      # Skip to next section (should land on section 2, skipping 1 remaining sentence in section 1)
      render_hook(view, :key_nav, %{"key" => "s"})

      # Check skip_range event
      event =
        ReadingEvent
        |> where([e], e.event_type == "skip_range")
        |> Repo.one()

      payload = ReadingEvent.decode_payload(event)
      # Should skip 1 remaining sentence from section 1 (sentence2)
      assert payload["skipped_sentences"] == 1
    end
  end

  describe "state transitions on toggle learning (l key)" do
    test "toggles learning state and logs mark_learning event", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola mundo.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})
      create_token(sentence.id, nil, %{position: 2, surface: "mundo", is_punctuation: false})

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Clear events
      Repo.delete_all(ReadingEvent)

      # Focus first token
      render_hook(view, :key_nav, %{"key" => "w"})

      # Toggle learning
      render_hook(view, :key_nav, %{"key" => "l"})

      # Should be marked as learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"

      # Should have logged mark_learning event
      events =
        ReadingEvent
        |> where([e], e.event_type == "mark_learning")
        |> Repo.all()

      assert length(events) == 1
      event = hd(events)
      assert event.token_id == token.id
      assert event.sentence_id == sentence.id

      payload = ReadingEvent.decode_payload(event)
      assert payload["lexeme_id"] == lexeme.id
      assert payload["new_status"] == "learning"
    end

    test "toggles back to seen and logs unmark_learning event", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola mundo.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})

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

      # Clear events
      Repo.delete_all(ReadingEvent)

      # Focus and toggle twice
      render_hook(view, :key_nav, %{"key" => "w"})
      render_hook(view, :key_nav, %{"key" => "l"})

      # Should have logged unmark_learning event
      events =
        ReadingEvent
        |> where([e], e.event_type == "unmark_learning")
        |> Repo.all()

      assert length(events) == 1
      event = hd(events)
      assert event.token_id == token.id

      payload = ReadingEvent.decode_payload(event)
      assert payload["new_status"] == "seen"
    end

    test "does nothing when no token is focused", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola.")
      create_tokens_for_sentence(sentence, ["Hola", "."])

      # Mount
      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Try to toggle without focusing a token
      render_hook(view, :key_nav, %{"key" => "l"})

      # Should not have created any learning events
      count =
        ReadingEvent
        |> where([e], e.event_type in ["mark_learning", "unmark_learning"])
        |> Repo.aggregate(:count, :id)

      assert count == 0
    end

    test "keeps known words unchanged when toggled", %{conn: conn} do
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

      # Should remain known
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      assert state.known_at != nil

      # Should not log learning toggle events
      count =
        ReadingEvent
        |> where([e], e.event_type in ["mark_learning", "unmark_learning"])
        |> Repo.aggregate(:count, :id)

      assert count == 0
    end

    test "does not toggle punctuation tokens", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola.")
      lexeme = create_lexeme(%{lemma: ".", normalized_lemma: ".", pos: "PUNCT"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: ".", is_punctuation: true})

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Click punctuation and try to toggle
      render_click(view, :focus_token, %{"token_index" => "1"})
      render_hook(view, :key_nav, %{"key" => "l"})

      assert Repo.aggregate(UserLexemeState, :count, :id) == 0
    end
  end

  describe "state transitions on help request (space key)" do
    test "space (popup closed) sets word to learning and opens popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})

      # Create a "seen" state (not learning, not known)
      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "seen",
          seen_count: 3,
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus token and press space (popup closed)
      render_hook(view, :key_nav, %{"key" => "w"})
      _html = render_hook(view, :key_nav, %{"key" => "space"})

      # Verify word is set to learning
      state = Repo.one(UserLexemeState)
      assert state.status == "learning"
      assert state.learning_since != nil

      # Verify popup is open
      assert has_element?(view, "[data-testid='llm-popup']")
    end

    test "space (popup open) sets word to known and closes popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hola.")
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})

      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 3,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second),
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus token, press space to open popup (sets to learning)
      render_hook(view, :key_nav, %{"key" => "w"})
      _html = render_hook(view, :key_nav, %{"key" => "space"})
      assert has_element?(view, "[data-testid='llm-popup']")

      # Press space again (popup open) - should set to known and close
      _html = render_hook(view, :key_nav, %{"key" => "space"})

      # Verify word is set to known
      state = Repo.one(UserLexemeState)
      assert state.status == "known"
      assert state.known_at != nil

      # Verify popup is closed
      refute has_element?(view, "[data-testid='llm-popup']")
    end
  end

  # Helper functions for creating test data

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
