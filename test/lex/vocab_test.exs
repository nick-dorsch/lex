defmodule Lex.VocabTest do
  use Lex.DataCase, async: true

  import Ecto.Query

  alias Lex.Vocab
  alias Lex.Vocab.UserLexemeState
  alias Lex.Repo

  # Helper function to create a user
  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Test User",
      email: "test#{unique_id}@example.com",
      primary_language: "en"
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Accounts.User{}
    |> Lex.Accounts.User.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a document
  defp create_document(user_id, attrs \\ %{}) do
    default_attrs = %{
      title: "Test Document",
      author: "Test Author",
      language: "es",
      status: "ready",
      source_file: "/path/to/file.epub",
      user_id: user_id
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Library.Document{}
    |> Lex.Library.Document.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a section
  defp create_section(document_id, position, attrs \\ %{}) do
    default_attrs = %{
      position: position,
      title: "Chapter #{position}",
      document_id: document_id
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Library.Section{}
    |> Lex.Library.Section.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a sentence
  defp create_sentence(section_id, position, text \\ "Test sentence.") do
    %Lex.Text.Sentence{}
    |> Lex.Text.Sentence.changeset(%{
      position: position,
      text: text,
      char_start: 0,
      char_end: String.length(text),
      section_id: section_id
    })
    |> Repo.insert!()
  end

  # Helper function to create a lexeme
  defp create_lexeme(attrs) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      language: "es",
      lemma: "test#{unique_id}",
      normalized_lemma: "test#{unique_id}",
      pos: "NOUN"
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Text.Lexeme{}
    |> Lex.Text.Lexeme.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a token
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

    %Lex.Text.Token{}
    |> Lex.Text.Token.changeset(attrs)
    |> Repo.insert!()
  end

  describe "mark_lexemes_seen/2" do
    test "first view creates seen entries for all non-punctuation tokens" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme1 = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme2 = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      # Create tokens for the sentence
      create_token(sentence.id, lexeme1.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme2.id, %{position: 2, surface: "mundo"})

      # Mark lexemes as seen
      assert {:ok, states} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      assert length(states) == 2

      # Verify each state
      Enum.each(states, fn state ->
        assert state.user_id == user.id
        assert state.status == "seen"
        assert state.seen_count == 1
        assert state.first_seen_at != nil
        assert state.last_seen_at != nil
      end)

      # Verify in database
      lexeme_ids = [lexeme1.id, lexeme2.id]
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      assert length(db_states) == 2
      assert Enum.map(db_states, & &1.lexeme_id) |> Enum.sort() == Enum.sort(lexeme_ids)
    end

    test "second view of same sentence doesn't duplicate entries" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # First view
      assert {:ok, [state1]} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      first_seen_at = state1.first_seen_at
      last_seen_at = state1.last_seen_at
      assert state1.seen_count == 1

      # Wait for timestamp to change (timestamps are truncated to seconds)
      Process.sleep(1100)

      # Second view
      assert {:ok, [state2]} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      assert state2.seen_count == 2
      assert state2.first_seen_at == first_seen_at
      assert DateTime.compare(state2.last_seen_at, last_seen_at) in [:gt, :eq]

      # Verify only one entry in database
      count = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.aggregate(:count, :id)
      assert count == 1
    end

    test "punctuation tokens are ignored" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme_word = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme_punct = create_lexeme(%{lemma: ".", normalized_lemma: ".", pos: "PUNCT"})

      # Create word token
      create_token(sentence.id, lexeme_word.id, %{position: 1, surface: "hola"})
      # Create punctuation token
      create_token(sentence.id, lexeme_punct.id, %{
        position: 2,
        surface: ".",
        is_punctuation: true
      })

      assert {:ok, states} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      assert length(states) == 1
      assert hd(states).lexeme_id == lexeme_word.id
    end

    test "learning words are not affected" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a "learning" state for the lexeme
      {:ok, learning_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 5,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Mark lexemes as seen - should not modify the learning state
      assert {:ok, [returned_state]} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      assert returned_state.status == "learning"
      assert returned_state.seen_count == 5
      assert returned_state.id == learning_state.id

      # Verify in database
      db_state = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.one()
      assert db_state.status == "learning"
      assert db_state.seen_count == 5
    end

    test "known words are not affected" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a "known" state for the lexeme
      {:ok, known_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 10,
          known_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Mark lexemes as seen - should not modify the known state
      assert {:ok, [returned_state]} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      assert returned_state.status == "known"
      assert returned_state.seen_count == 10
      assert returned_state.id == known_state.id

      # Verify in database
      db_state = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.one()
      assert db_state.status == "known"
      assert db_state.seen_count == 10
    end

    test "repeated tokens in sentence are handled correctly" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create two tokens with the same lexeme
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 2, surface: "hola"})

      assert {:ok, states} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      # Should only have one state despite two tokens
      assert length(states) == 1
      assert hd(states).seen_count == 1

      # Verify only one entry in database
      count = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.aggregate(:count, :id)
      assert count == 1
    end

    test "tokens without lexeme_id are ignored" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create token with lexeme
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})
      # Create token without lexeme
      create_token(sentence.id, nil, %{position: 2, surface: "test"})

      assert {:ok, states} = Vocab.mark_lexemes_seen(user.id, sentence.id)
      assert length(states) == 1
      assert hd(states).lexeme_id == lexeme.id
    end

    test "multiple users can have separate states for same lexeme" do
      user1 = create_user(%{email: "user1@example.com"})
      user2 = create_user(%{email: "user2@example.com"})
      document = create_document(user1.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Both users view the sentence
      assert {:ok, [state1]} = Vocab.mark_lexemes_seen(user1.id, sentence.id)
      assert {:ok, [state2]} = Vocab.mark_lexemes_seen(user2.id, sentence.id)

      assert state1.user_id == user1.id
      assert state2.user_id == user2.id
      assert state1.lexeme_id == state2.lexeme_id
      assert state1.id != state2.id

      # Verify two separate entries in database
      count =
        UserLexemeState |> where([s], s.lexeme_id == ^lexeme.id) |> Repo.aggregate(:count, :id)

      assert count == 2
    end

    test "empty sentence returns empty list" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # No tokens in the sentence
      assert {:ok, []} = Vocab.mark_lexemes_seen(user.id, sentence.id)
    end

    test "sentence with only punctuation returns empty list" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme_punct = create_lexeme(%{lemma: ".", normalized_lemma: ".", pos: "PUNCT"})

      create_token(sentence.id, lexeme_punct.id, %{
        position: 1,
        surface: ".",
        is_punctuation: true
      })

      assert {:ok, []} = Vocab.mark_lexemes_seen(user.id, sentence.id)
    end
  end

  describe "toggle_learning/2" do
    test "toggles from new (no state) to learning" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      assert {:ok, state} = Vocab.toggle_learning(user.id, lexeme.id)
      assert state.status == "learning"
      assert state.learning_since != nil
      assert state.seen_count == 1
      assert state.first_seen_at != nil
      assert state.last_seen_at != nil
    end

    test "toggles from seen to learning" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # First mark as seen
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Get the state
      seen_state = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.one()
      assert seen_state.status == "seen"
      assert seen_state.learning_since == nil

      # Toggle to learning
      assert {:ok, learning_state} = Vocab.toggle_learning(user.id, lexeme.id)
      assert learning_state.status == "learning"
      assert learning_state.learning_since != nil
      # Incremented
      assert learning_state.seen_count == 2
    end

    test "toggles from learning back to seen" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create a learning state
      {:ok, learning_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 5,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second),
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      assert learning_state.status == "learning"

      # Toggle back to seen
      assert {:ok, seen_state} = Vocab.toggle_learning(user.id, lexeme.id)
      assert seen_state.status == "seen"
      assert seen_state.learning_since == nil
      # Incremented
      assert seen_state.seen_count == 6
    end

    test "known words remain known when toggled" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create a known state
      known_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, known_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 10,
          known_at: known_at,
          first_seen_at: known_at,
          last_seen_at: known_at
        })
        |> Repo.insert()

      assert known_state.status == "known"

      # Toggle should keep known words unchanged
      assert {:ok, unchanged_state} = Vocab.toggle_learning(user.id, lexeme.id)
      assert unchanged_state.status == "known"
      assert unchanged_state.learning_since == nil
      assert unchanged_state.known_at == known_at
      assert unchanged_state.seen_count == 10
    end

    test "sets learning_since timestamp when toggling to learning" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      before_toggle = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, state} = Vocab.toggle_learning(user.id, lexeme.id)

      after_toggle = DateTime.utc_now() |> DateTime.truncate(:second)

      assert state.status == "learning"
      assert state.learning_since != nil
      assert DateTime.compare(state.learning_since, before_toggle) in [:gt, :eq]
      assert DateTime.compare(state.learning_since, after_toggle) in [:lt, :eq]
    end

    test "clears learning_since when toggling from learning to seen" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create a learning state
      {:ok, _} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 5,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second),
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      assert {:ok, state} = Vocab.toggle_learning(user.id, lexeme.id)
      assert state.status == "seen"
      assert state.learning_since == nil
    end
  end

  describe "promote_seen_to_known/2" do
    test "promotes seen words to known on sentence advance" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme1 = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme2 = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      # Create tokens for the sentence
      create_token(sentence.id, lexeme1.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme2.id, %{position: 2, surface: "mundo"})

      # First mark lexemes as seen (simulating viewing the sentence)
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Verify initial state
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      assert length(db_states) == 2
      assert Enum.all?(db_states, fn s -> s.status == "seen" end)

      # Now promote to known
      assert {:ok, 2} = Vocab.promote_seen_to_known(user.id, sentence.id)

      # Verify promoted state
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      assert length(db_states) == 2
      assert Enum.all?(db_states, fn s -> s.status == "known" end)
      assert Enum.all?(db_states, fn s -> s.known_at != nil end)
    end

    test "learning words remain unchanged" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme1 = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme2 = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence.id, lexeme1.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme2.id, %{position: 2, surface: "mundo"})

      # Mark as seen first
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Manually set one to learning
      UserLexemeState
      |> where([s], s.user_id == ^user.id and s.lexeme_id == ^lexeme1.id)
      |> Repo.update_all(set: [status: "learning", learning_since: DateTime.utc_now()])

      # Promote to known
      assert {:ok, 1} = Vocab.promote_seen_to_known(user.id, sentence.id)

      # Verify only the seen word was promoted
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      learning_state = Enum.find(db_states, fn s -> s.lexeme_id == lexeme1.id end)
      known_state = Enum.find(db_states, fn s -> s.lexeme_id == lexeme2.id end)

      assert learning_state.status == "learning"
      assert known_state.status == "known"
      assert known_state.known_at != nil
    end

    test "known words remain unchanged" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme1 = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme2 = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})

      create_token(sentence.id, lexeme1.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme2.id, %{position: 2, surface: "mundo"})

      # Mark as seen first
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Manually set one to known
      original_known_at = DateTime.utc_now() |> DateTime.truncate(:second)

      UserLexemeState
      |> where([s], s.user_id == ^user.id and s.lexeme_id == ^lexeme1.id)
      |> Repo.update_all(set: [status: "known", known_at: original_known_at])

      # Wait a moment to ensure timestamps would differ
      Process.sleep(1100)

      # Promote to known
      assert {:ok, 1} = Vocab.promote_seen_to_known(user.id, sentence.id)

      # Verify only the seen word was promoted
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      already_known = Enum.find(db_states, fn s -> s.lexeme_id == lexeme1.id end)
      newly_known = Enum.find(db_states, fn s -> s.lexeme_id == lexeme2.id end)

      assert already_known.status == "known"
      assert already_known.known_at == original_known_at
      assert newly_known.status == "known"
      assert newly_known.known_at != nil
      assert DateTime.compare(newly_known.known_at, original_known_at) == :gt
    end

    test "punctuation is ignored" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme_word = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme_punct = create_lexeme(%{lemma: ".", normalized_lemma: ".", pos: "PUNCT"})

      create_token(sentence.id, lexeme_word.id, %{position: 1, surface: "hola"})

      create_token(sentence.id, lexeme_punct.id, %{
        position: 2,
        surface: ".",
        is_punctuation: true
      })

      # Mark as seen
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Promote
      assert {:ok, 1} = Vocab.promote_seen_to_known(user.id, sentence.id)

      # Verify only word was promoted
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      assert length(db_states) == 1
      assert hd(db_states).status == "known"
    end

    test "returns count of promoted words" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme1 = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      lexeme2 = create_lexeme(%{lemma: "mundo", normalized_lemma: "mundo"})
      lexeme3 = create_lexeme(%{lemma: "bien", normalized_lemma: "bien"})

      create_token(sentence.id, lexeme1.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme2.id, %{position: 2, surface: "mundo"})
      create_token(sentence.id, lexeme3.id, %{position: 3, surface: "bien"})

      # Mark as seen
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Set one to known
      UserLexemeState
      |> where([s], s.user_id == ^user.id and s.lexeme_id == ^lexeme1.id)
      |> Repo.update_all(set: [status: "known"])

      # Promote should return 2 (only seen words)
      assert {:ok, 2} = Vocab.promote_seen_to_known(user.id, sentence.id)
    end

    test "empty sentence returns 0" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      assert {:ok, 0} = Vocab.promote_seen_to_known(user.id, sentence.id)
    end

    test "sentence with only punctuation returns 0" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme_punct = create_lexeme(%{lemma: ".", normalized_lemma: ".", pos: "PUNCT"})

      create_token(sentence.id, lexeme_punct.id, %{
        position: 1,
        surface: ".",
        is_punctuation: true
      })

      assert {:ok, 0} = Vocab.promote_seen_to_known(user.id, sentence.id)
    end

    test "only affects specified user" do
      user1 = create_user(%{email: "user1@example.com"})
      user2 = create_user(%{email: "user2@example.com"})
      document = create_document(user1.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Both users see the sentence
      assert {:ok, _} = Vocab.mark_lexemes_seen(user1.id, sentence.id)
      assert {:ok, _} = Vocab.mark_lexemes_seen(user2.id, sentence.id)

      # Only promote for user1
      assert {:ok, 1} = Vocab.promote_seen_to_known(user1.id, sentence.id)

      # Verify user1's state is known
      user1_state = UserLexemeState |> where([s], s.user_id == ^user1.id) |> Repo.one()
      assert user1_state.status == "known"

      # Verify user2's state is still seen
      user2_state = UserLexemeState |> where([s], s.user_id == ^user2.id) |> Repo.one()
      assert user2_state.status == "seen"
    end

    test "repeated lexemes in sentence handled correctly" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create multiple tokens with same lexeme
      create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 2, surface: "hola"})
      create_token(sentence.id, lexeme.id, %{position: 3, surface: "hola"})

      # Mark as seen
      assert {:ok, _} = Vocab.mark_lexemes_seen(user.id, sentence.id)

      # Promote should return 1 (only one lexeme, despite multiple tokens)
      assert {:ok, 1} = Vocab.promote_seen_to_known(user.id, sentence.id)

      # Verify state
      db_states = UserLexemeState |> where([s], s.user_id == ^user.id) |> Repo.all()
      assert length(db_states) == 1
      assert hd(db_states).status == "known"
    end
  end

  describe "mark_learning/2" do
    test "creates new learning state for new lexeme" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      assert {:ok, state} = Vocab.mark_learning(user.id, lexeme.id)
      assert state.user_id == user.id
      assert state.lexeme_id == lexeme.id
      assert state.status == "learning"
      assert state.learning_since != nil
      assert state.seen_count == 1
      assert state.first_seen_at != nil
      assert state.last_seen_at != nil
    end

    test "promotes seen lexeme to learning" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create a seen state first
      {:ok, seen_state} =
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

      assert seen_state.status == "seen"
      assert seen_state.learning_since == nil

      # Mark as learning
      assert {:ok, learning_state} = Vocab.mark_learning(user.id, lexeme.id)
      assert learning_state.status == "learning"
      assert learning_state.learning_since != nil
      assert learning_state.seen_count == 4
      assert learning_state.id == seen_state.id
    end

    test "does not change already learning lexeme" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      learning_since = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create a learning state
      {:ok, original_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 5,
          learning_since: learning_since,
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Mark as learning again
      assert {:ok, state} = Vocab.mark_learning(user.id, lexeme.id)
      assert state.status == "learning"
      assert state.learning_since == learning_since
      assert state.seen_count == 5
      assert state.id == original_state.id
    end

    test "promotes known lexeme to learning" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      # Create a known state
      {:ok, known_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 10,
          known_at: DateTime.utc_now() |> DateTime.truncate(:second),
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      assert known_state.status == "known"

      # Mark as learning (should still work for known words)
      assert {:ok, learning_state} = Vocab.mark_learning(user.id, lexeme.id)
      assert learning_state.status == "learning"
      assert learning_state.learning_since != nil
      assert learning_state.seen_count == 11
      assert learning_state.id == known_state.id
    end

    test "sets learning_since timestamp" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      before = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, state} = Vocab.mark_learning(user.id, lexeme.id)

      after_mark = DateTime.utc_now() |> DateTime.truncate(:second)

      assert state.learning_since != nil
      assert DateTime.compare(state.learning_since, before) in [:gt, :eq]
      assert DateTime.compare(state.learning_since, after_mark) in [:lt, :eq]
    end
  end

  describe "advance_help_state/2" do
    test "creates learning state for unseen lexeme" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      assert {:ok, state} = Vocab.advance_help_state(user.id, lexeme.id)
      assert state.status == "learning"
      assert state.learning_since != nil
      assert state.known_at == nil
      assert state.seen_count == 1
    end

    test "promotes learning lexeme to known" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      {:ok, learning_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "learning",
          seen_count: 2,
          learning_since: DateTime.utc_now() |> DateTime.truncate(:second),
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      assert {:ok, known_state} = Vocab.advance_help_state(user.id, lexeme.id)
      assert known_state.id == learning_state.id
      assert known_state.status == "known"
      assert known_state.known_at != nil
      assert known_state.seen_count == 3
    end

    test "promotes seen lexeme to learning" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})

      {:ok, seen_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "seen",
          seen_count: 2,
          first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      assert {:ok, learning_state} = Vocab.advance_help_state(user.id, lexeme.id)
      assert learning_state.id == seen_state.id
      assert learning_state.status == "learning"
      assert learning_state.learning_since != nil
      assert learning_state.seen_count == 3
    end

    test "moves known lexeme back to learning" do
      user = create_user()
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      known_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, known_state} =
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user.id,
          lexeme_id: lexeme.id,
          status: "known",
          seen_count: 8,
          known_at: known_at,
          first_seen_at: known_at,
          last_seen_at: known_at
        })
        |> Repo.insert()

      assert {:ok, relearning_state} = Vocab.advance_help_state(user.id, lexeme.id)
      assert relearning_state.id == known_state.id
      assert relearning_state.status == "learning"
      assert relearning_state.learning_since != nil
      assert relearning_state.known_at == nil
      assert relearning_state.seen_count == 9
    end
  end

  describe "log_llm_request/5" do
    test "logs token-level LLM help request" do
      user = create_user()
      document = create_document(user.id, %{language: "es"})
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      assert {:ok, request} =
               Vocab.log_llm_request(user.id, document.id, sentence.id, token.id, :token)

      assert request.user_id == user.id
      assert request.document_id == document.id
      assert request.sentence_id == sentence.id
      assert request.token_id == token.id
      assert request.request_type == "token"
      assert request.response_language == "es"
      assert request.provider == Application.get_env(:lex, :llm_provider, "openai")
      assert request.model == Application.get_env(:lex, :llm_model, "gpt-4o-mini")
      assert request.inserted_at != nil
    end

    test "logs sentence-level LLM help request" do
      user = create_user()
      document = create_document(user.id, %{language: "fr"})
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      assert {:ok, request} =
               Vocab.log_llm_request(user.id, document.id, sentence.id, nil, :sentence)

      assert request.user_id == user.id
      assert request.document_id == document.id
      assert request.sentence_id == sentence.id
      assert request.token_id == nil
      assert request.request_type == "sentence"
      assert request.response_language == "fr"
      assert request.provider == Application.get_env(:lex, :llm_provider, "openai")
      assert request.model == Application.get_env(:lex, :llm_model, "gpt-4o-mini")
    end

    test "uses document language for response_language" do
      user = create_user()
      document = create_document(user.id, %{language: "de"})
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      assert {:ok, request} =
               Vocab.log_llm_request(user.id, document.id, sentence.id, nil, :sentence)

      assert request.response_language == "de"
    end

    test "returns error for invalid document_id" do
      user = create_user()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Vocab.log_llm_request(user.id, 999_999, 1, nil, :sentence)

      assert changeset.errors[:document_id]
    end

    test "returns error for token-level request without token_id" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Vocab.log_llm_request(user.id, document.id, sentence.id, nil, :token)

      assert changeset.errors[:token_id]
    end
  end

  describe "get_cached_llm_response/3" do
    test "returns cached response when available" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a cached response
      {:ok, request} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: "This means hello in Spanish."
        })
        |> Repo.insert()

      assert {:ok, cached} = Vocab.get_cached_llm_response(sentence.id, token.id, "en")
      assert cached.id == request.id
      assert cached.response_text == "This means hello in Spanish."
    end

    test "returns not_found when no cached response" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      assert {:error, :not_found} = Vocab.get_cached_llm_response(sentence.id, token.id, "en")
    end

    test "returns not_found for pending response (nil response_text)" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a pending request (no response_text)
      {:ok, _} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: nil
        })
        |> Repo.insert()

      assert {:error, :not_found} = Vocab.get_cached_llm_response(sentence.id, token.id, "en")
    end

    test "respects response_language filter" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create cached response in Spanish
      {:ok, _} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "es",
          provider: "openai",
          model: "gpt-4",
          response_text: "Esto significa hola en español."
        })
        |> Repo.insert()

      # Query for English should not find it
      assert {:error, :not_found} = Vocab.get_cached_llm_response(sentence.id, token.id, "en")

      # Query for Spanish should find it
      assert {:ok, _} = Vocab.get_cached_llm_response(sentence.id, token.id, "es")
    end

    test "returns a cached response when multiple exist" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create first cached response
      {:ok, first_request} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: "First response."
        })
        |> Repo.insert()

      Process.sleep(100)

      # Create second cached response
      {:ok, second_request} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: "Second response."
        })
        |> Repo.insert()

      # Should return one of the cached responses
      assert {:ok, cached} = Vocab.get_cached_llm_response(sentence.id, token.id, "en")
      assert cached.response_text in ["First response.", "Second response."]
      assert cached.id in [first_request.id, second_request.id]
    end
  end

  describe "build_llm_prompt/4" do
    test "builds correct system and user prompts" do
      user = create_user(%{primary_language: "en"})
      document = create_document(user.id, %{title: "El Quijote", author: "Cervantes"})
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1, "Hola mundo cruel.")

      token = %Lex.Text.Token{
        surface: "mundo",
        lemma: "mundo",
        pos: "NOUN"
      }

      {system_msg, user_msg} = Vocab.build_llm_prompt(token, sentence, document, user)

      assert system_msg =~ "You are a language learner's reading assistant"
      assert system_msg =~ "Translate from #{document.language} into en."
      assert user_msg =~ "Word: mundo (lemma: mundo, pos: NOUN)"
      assert user_msg =~ "Sentence context: Hola mundo cruel."
      assert user_msg =~ "Source: El Quijote by Cervantes"
    end

    test "uses user primary_language for response" do
      user = create_user(%{primary_language: "fr"})
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      token = %Lex.Text.Token{
        surface: "test",
        lemma: "test",
        pos: "NOUN"
      }

      {_system_msg, user_msg} = Vocab.build_llm_prompt(token, sentence, document, user)

      refute user_msg =~ "Respond in"
    end
  end

  describe "finalize_llm_request/5" do
    test "updates request with response data" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a pending request
      {:ok, request} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: nil
        })
        |> Repo.insert()

      # Finalize the request
      assert {:ok, finalized} =
               Vocab.finalize_llm_request(request.id, "This means hello.", 1234, 10, 25)

      assert finalized.id == request.id
      assert finalized.response_text == "This means hello."
      assert finalized.latency_ms == 1234
      assert finalized.prompt_tokens == 10
      assert finalized.completion_tokens == 25
    end

    test "returns error for non-existent request" do
      assert {:error, :not_found} =
               Vocab.finalize_llm_request(999_999, "test", 100, 10, 20)
    end

    test "allows nil values for optional fields" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a pending request
      {:ok, request} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: nil
        })
        |> Repo.insert()

      # Finalize with nil values (e.g., on error)
      assert {:ok, finalized} =
               Vocab.finalize_llm_request(request.id, nil, nil, nil, nil)

      assert finalized.response_text == nil
      assert finalized.latency_ms == nil
      assert finalized.prompt_tokens == nil
      assert finalized.completion_tokens == nil
    end
  end

  describe "request_llm_help/5" do
    test "returns cached response when available" do
      user = create_user(%{primary_language: "en"})
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Create a cached response
      {:ok, cached_request} =
        %Lex.Vocab.LlmHelpRequest{}
        |> Lex.Vocab.LlmHelpRequest.changeset(%{
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id,
          request_type: "token",
          response_language: "en",
          provider: "openai",
          model: "gpt-4",
          response_text: "Cached explanation."
        })
        |> Repo.insert()

      callback = fn event ->
        send(self(), {:callback, event})
      end

      assert {:ok, request_id, start_time} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, token.id, callback)

      assert request_id == cached_request.id
      # Cached responses have nil start_time
      assert start_time == nil

      # Verify callback received cached event
      assert_receive {:callback, {:cached, "Cached explanation."}}, 1000
    end

    test "returns error when user not found" do
      callback = fn _event -> :ok end

      assert {:error, :user_not_found} =
               Vocab.request_llm_help(999_999, 1, 1, 1, callback)
    end

    test "returns error when token not found" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      callback = fn _event -> :ok end

      assert {:error, :token_not_found} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, 999_999, callback)
    end

    test "returns error when required data not found" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      callback = fn _event -> :ok end

      # Pass invalid document_id
      assert {:error, :required_data_not_found} =
               Vocab.request_llm_help(user.id, 999_999, sentence.id, token.id, callback)
    end

    test "returns error when LLM not configured" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Clear LLM configuration and disable mock client to test real configuration checking
      original_api_key = Application.get_env(:lex, :llm_api_key)
      original_base_url = Application.get_env(:lex, :llm_base_url)
      original_client = Application.get_env(:lex, :llm_client)

      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_api_key, nil)
      Application.put_env(:lex, :llm_base_url, nil)

      callback = fn _event -> :ok end

      assert {:error, :not_configured} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, token.id, callback)

      # Restore configuration
      Application.put_env(:lex, :llm_api_key, original_api_key)
      Application.put_env(:lex, :llm_base_url, original_base_url)
      Application.put_env(:lex, :llm_client, original_client)
    end

    test "creates request record for new request" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Save original config
      original_api_key = Application.get_env(:lex, :llm_api_key)
      original_base_url = Application.get_env(:lex, :llm_base_url)

      # Set up a mock configuration
      Application.put_env(:lex, :llm_api_key, "test-key")
      Application.put_env(:lex, :llm_base_url, "https://api.test.com")

      callback = fn _event -> :ok end

      # Should create a request even though LLM call will fail in tests
      assert {:ok, _request_id, start_time} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, token.id, callback)

      # Streaming requests have a valid start_time
      assert start_time != nil
      assert is_integer(start_time)

      # Verify a request was created
      requests =
        Lex.Vocab.LlmHelpRequest
        |> where([r], r.sentence_id == ^sentence.id and r.token_id == ^token.id)
        |> Repo.all()

      assert length(requests) >= 1

      # Clean up
      Application.put_env(:lex, :llm_api_key, original_api_key)
      Application.put_env(:lex, :llm_base_url, original_base_url)
    end

    test "calculates and passes latency_ms in stats on completion" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Save original config
      original_client = Application.get_env(:lex, :llm_client)

      # Configure mock client
      Application.put_env(:lex, :llm_client, Lex.LLM.ClientMock)
      Lex.LLM.ClientMock.set_mock_response("Test response")
      Lex.LLM.ClientMock.set_chunk_delay(0)

      parent = self()

      callback = fn event ->
        send(parent, {:test_callback, event})
      end

      assert {:ok, _request_id, start_time} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, token.id, callback)

      # Streaming requests have a valid start_time
      assert start_time != nil
      assert is_integer(start_time)

      # Wait for the :done event with a longer timeout
      stats =
        receive do
          {:test_callback, {:done, s}} -> s
        after
          2000 -> nil
        end

      assert stats != nil, "Expected to receive :done event with stats"
      assert stats[:latency_ms] != nil, "Expected latency_ms to be present in stats"
      assert stats[:latency_ms] >= 0, "Expected latency_ms to be non-negative"

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
      Application.put_env(:lex, :llm_client, original_client)
    end

    test "persists latency when finalizing streaming response" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Save original config
      original_client = Application.get_env(:lex, :llm_client)

      # Configure mock client
      Application.put_env(:lex, :llm_client, Lex.LLM.ClientMock)
      Lex.LLM.ClientMock.set_mock_response("Test explanation")
      Lex.LLM.ClientMock.set_chunk_delay(0)

      parent = self()

      callback = fn event ->
        send(parent, {:test_callback, event})
      end

      assert {:ok, request_id, start_time} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, token.id, callback)

      # Streaming requests have a valid start_time
      assert start_time != nil
      assert is_integer(start_time)

      # Wait for the :done event with stats
      stats =
        receive do
          {:test_callback, {:done, s}} -> s
        after
          2000 -> nil
        end

      assert stats != nil, "Expected to receive :done event with stats"
      assert stats[:latency_ms] != nil, "Expected latency_ms to be present in stats"
      assert stats[:latency_ms] >= 0, "Expected latency_ms to be non-negative"

      # Flush remaining events
      Enum.each(1..10, fn _ ->
        receive do
          {:test_callback, _} -> :ok
        after
          50 -> :ok
        end
      end)

      # Finalize with the latency from stats
      assert {:ok, finalized} =
               Vocab.finalize_llm_request(
                 request_id,
                 "Test explanation",
                 stats[:latency_ms],
                 stats[:prompt_tokens],
                 stats[:completion_tokens]
               )

      assert finalized.latency_ms == stats[:latency_ms]
      assert finalized.latency_ms >= 0

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
      Application.put_env(:lex, :llm_client, original_client)
    end

    test "persists latency on not_configured error finalization" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
      token = create_token(sentence.id, lexeme.id, %{position: 1, surface: "hola"})

      # Clear LLM configuration to trigger :not_configured error
      original_api_key = Application.get_env(:lex, :llm_api_key)
      original_base_url = Application.get_env(:lex, :llm_base_url)
      original_client = Application.get_env(:lex, :llm_client)

      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_api_key, nil)
      Application.put_env(:lex, :llm_base_url, nil)

      callback = fn _event -> :ok end

      # Request should fail with :not_configured
      assert {:error, :not_configured} =
               Vocab.request_llm_help(user.id, document.id, sentence.id, token.id, callback)

      # Find the created request and verify it was finalized with latency
      requests =
        Lex.Vocab.LlmHelpRequest
        |> where([r], r.sentence_id == ^sentence.id and r.token_id == ^token.id)
        |> Repo.all()

      assert length(requests) >= 1

      request = List.first(requests)
      # The request should have been finalized with a latency value
      assert request.latency_ms != nil
      assert request.latency_ms >= 0

      # Restore configuration
      Application.put_env(:lex, :llm_api_key, original_api_key)
      Application.put_env(:lex, :llm_base_url, original_base_url)
      Application.put_env(:lex, :llm_client, original_client)
    end
  end
end
