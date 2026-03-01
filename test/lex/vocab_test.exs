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
end
