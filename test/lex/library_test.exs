defmodule Lex.LibraryTest do
  use Lex.DataCase, async: true

  import Ecto.Query

  alias Lex.Library
  alias Lex.Library.{Document, Section}
  alias Lex.Repo
  alias Lex.Text.{Lexeme, Sentence, Token}

  describe "import_epub/2" do
    setup do
      # Create a test user with unique email
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      {:ok, user: user}
    end

    test "successfully imports El Principito complete book", %{user: user} do
      # Mock the NLP.process_text call to return test data
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:ok,
         [
           %{
             "position" => 1,
             "text" => "Hola mundo.",
             "char_start" => 0,
             "char_end" => 11,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "Hola",
                 "normalized_surface" => "hola",
                 "lemma" => "hola",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 0,
                 "char_end" => 4
               },
               %{
                 "position" => 2,
                 "surface" => "mundo",
                 "normalized_surface" => "mundo",
                 "lemma" => "mundo",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 5,
                 "char_end" => 10
               },
               %{
                 "position" => 3,
                 "surface" => ".",
                 "normalized_surface" => ".",
                 "lemma" => ".",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 10,
                 "char_end" => 11
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"

        assert {:ok, document} = Library.import_epub(path, user_id: user.id)

        # Verify document was created with correct metadata
        assert document.title == "El Principito"
        assert document.author == "Antoine de Saint-Exupéry"
        assert document.language == "es"
        assert document.status == "ready"
        assert document.user_id == user.id
        assert document.source_file == path

        # Verify sections were created
        sections =
          Repo.all(from(s in Section, where: s.document_id == ^document.id, order_by: s.position))

        assert length(sections) == 1
        [section] = sections
        assert section.position == 1
        assert section.title == "Chapter 1"
        assert section.source_href == "chapter1.xhtml"

        # Verify sentences were created
        sentences =
          Repo.all(from(s in Sentence, where: s.section_id == ^section.id, order_by: s.position))

        assert length(sentences) == 1
        [sentence] = sentences
        assert sentence.position == 1
        assert sentence.text == "Hola mundo."
        assert sentence.char_start == 0
        assert sentence.char_end == 11

        # Verify tokens were created
        tokens =
          Repo.all(from(t in Token, where: t.sentence_id == ^sentence.id, order_by: t.position))

        assert length(tokens) == 3

        [token1, token2, token3] = tokens
        assert token1.position == 1
        assert token1.surface == "Hola"
        assert token1.normalized_surface == "hola"
        assert token1.lemma == "hola"
        assert token1.pos == "NOUN"
        assert token1.is_punctuation == false

        assert token2.position == 2
        assert token2.surface == "mundo"
        assert token2.normalized_surface == "mundo"

        assert token3.position == 3
        assert token3.surface == "."
        assert token3.is_punctuation == true

        # Verify lexemes were created
        lexemes = Repo.all(from(l in Lexeme))
        assert length(lexemes) == 3

        # Verify tokens are linked to lexemes
        assert token1.lexeme_id != nil
        assert token2.lexeme_id != nil
        assert token3.lexeme_id != nil
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "creates all Sections in order for multi-chapter EPUB", %{user: user} do
      # Mock NLP to return simple data for each chapter
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:ok,
         [
           %{
             "position" => 1,
             "text" => "Test sentence.",
             "char_start" => 0,
             "char_end" => 14,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "Test",
                 "normalized_surface" => "test",
                 "lemma" => "test",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 0,
                 "char_end" => 4
               },
               %{
                 "position" => 2,
                 "surface" => "sentence",
                 "normalized_surface" => "sentence",
                 "lemma" => "sentence",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 5,
                 "char_end" => 13
               },
               %{
                 "position" => 3,
                 "surface" => ".",
                 "normalized_surface" => ".",
                 "lemma" => ".",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 13,
                 "char_end" => 14
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/multi_chapter.epub"
        assert {:ok, document} = Library.import_epub(path, user_id: user.id)

        # Should have 3 sections (excluding front/back matter)
        sections =
          Repo.all(from(s in Section, where: s.document_id == ^document.id, order_by: s.position))

        assert length(sections) == 3

        [ch1, ch2, ch3] = sections
        assert ch1.position == 1
        assert ch1.title == "Chapter 1"
        assert ch2.position == 2
        assert ch2.title == "Chapter 2"
        assert ch3.position == 3
        assert ch3.title == "Chapter 3"
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "returns error when EPUB parse fails", %{user: user} do
      assert {:error, {:epub_parse_failed, :file_not_found}} =
               Library.import_epub("/nonexistent/file.epub", user_id: user.id)
    end

    test "returns error when NLP fails", %{user: user} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:error, :python_not_found}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"

        assert {:error, {:nlp_failed, "Chapter 1", :python_not_found}} =
                 Library.import_epub(path, user_id: user.id)
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "transaction rolls back on any failure", %{user: user} do
      # Count records before
      doc_count_before = Repo.aggregate(Document, :count)
      section_count_before = Repo.aggregate(Section, :count)
      sentence_count_before = Repo.aggregate(Sentence, :count)
      token_count_before = Repo.aggregate(Token, :count)
      lexeme_count_before = Repo.aggregate(Lexeme, :count)

      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:error, :timeout}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"
        assert {:error, {:nlp_failed, _, _}} = Library.import_epub(path, user_id: user.id)

        # Verify no records were created (transaction rolled back)
        assert Repo.aggregate(Document, :count) == doc_count_before
        assert Repo.aggregate(Section, :count) == section_count_before
        assert Repo.aggregate(Sentence, :count) == sentence_count_before
        assert Repo.aggregate(Token, :count) == token_count_before
        assert Repo.aggregate(Lexeme, :count) == lexeme_count_before
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "uses source_file override when provided", %{user: user} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:ok,
         [
           %{
             "position" => 1,
             "text" => "Hola mundo.",
             "char_start" => 0,
             "char_end" => 11,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "Hola",
                 "normalized_surface" => "hola",
                 "lemma" => "hola",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 0,
                 "char_end" => 4
               },
               %{
                 "position" => 2,
                 "surface" => "mundo",
                 "normalized_surface" => "mundo",
                 "lemma" => "mundo",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 5,
                 "char_end" => 10
               },
               %{
                 "position" => 3,
                 "surface" => ".",
                 "normalized_surface" => ".",
                 "lemma" => ".",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 10,
                 "char_end" => 11
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"
        override_path = "/custom/path/to/book.epub"

        assert {:ok, document} =
                 Library.import_epub(path, user_id: user.id, source_file: override_path)

        assert document.source_file == override_path
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "creates Sentences and Tokens with correct positions", %{user: user} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:ok,
         [
           %{
             "position" => 1,
             "text" => "First sentence.",
             "char_start" => 0,
             "char_end" => 15,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "First",
                 "normalized_surface" => "first",
                 "lemma" => "first",
                 "pos" => "ADJ",
                 "is_punctuation" => false,
                 "char_start" => 0,
                 "char_end" => 5
               },
               %{
                 "position" => 2,
                 "surface" => "sentence",
                 "normalized_surface" => "sentence",
                 "lemma" => "sentence",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 6,
                 "char_end" => 14
               },
               %{
                 "position" => 3,
                 "surface" => ".",
                 "normalized_surface" => ".",
                 "lemma" => ".",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 14,
                 "char_end" => 15
               }
             ]
           },
           %{
             "position" => 2,
             "text" => "Second sentence!",
             "char_start" => 16,
             "char_end" => 32,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "Second",
                 "normalized_surface" => "second",
                 "lemma" => "second",
                 "pos" => "ADJ",
                 "is_punctuation" => false,
                 "char_start" => 16,
                 "char_end" => 22
               },
               %{
                 "position" => 2,
                 "surface" => "sentence",
                 "normalized_surface" => "sentence",
                 "lemma" => "sentence",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 23,
                 "char_end" => 31
               },
               %{
                 "position" => 3,
                 "surface" => "!",
                 "normalized_surface" => "!",
                 "lemma" => "!",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 31,
                 "char_end" => 32
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"
        assert {:ok, document} = Library.import_epub(path, user_id: user.id)

        section = Repo.one!(from(s in Section, where: s.document_id == ^document.id))

        sentences =
          Repo.all(from(s in Sentence, where: s.section_id == ^section.id, order_by: s.position))

        assert length(sentences) == 2

        [sent1, sent2] = sentences
        assert sent1.position == 1
        assert sent1.text == "First sentence."
        assert sent2.position == 2
        assert sent2.text == "Second sentence!"

        # Verify tokens for first sentence
        tokens1 =
          Repo.all(from(t in Token, where: t.sentence_id == ^sent1.id, order_by: t.position))

        assert length(tokens1) == 3
        assert Enum.map(tokens1, & &1.position) == [1, 2, 3]

        # Verify tokens for second sentence
        tokens2 =
          Repo.all(from(t in Token, where: t.sentence_id == ^sent2.id, order_by: t.position))

        assert length(tokens2) == 3
        assert Enum.map(tokens2, & &1.position) == [1, 2, 3]
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "reuses existing Lexemes for same language/lemma/pos combination", %{user: user} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      call_count = :atomics.new(1, signed: false)

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        # Track how many times NLP is called (once per chapter)
        :atomics.add_get(call_count, 1, 1)

        {:ok,
         [
           %{
             "position" => 1,
             "text" => "Test sentence.",
             "char_start" => 0,
             "char_end" => 14,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "Test",
                 "normalized_surface" => "test",
                 "lemma" => "test",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 0,
                 "char_end" => 4
               },
               %{
                 "position" => 2,
                 "surface" => "sentence",
                 "normalized_surface" => "sentence",
                 "lemma" => "sentence",
                 "pos" => "NOUN",
                 "is_punctuation" => false,
                 "char_start" => 5,
                 "char_end" => 13
               },
               %{
                 "position" => 3,
                 "surface" => ".",
                 "normalized_surface" => ".",
                 "lemma" => ".",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 13,
                 "char_end" => 14
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/multi_chapter.epub"
        assert {:ok, _document} = Library.import_epub(path, user_id: user.id)

        # Should have 3 NLP calls (one per chapter)
        assert :atomics.get(call_count, 1) == 3

        # Lexemes for "test", "sentence", and "." should only be created once each
        # even though they appear in all 3 chapters
        lexemes = Repo.all(from(l in Lexeme))

        # We should have exactly 3 lexemes (test, sentence, .)
        # because they're reused across chapters
        assert length(lexemes) == 3

        # Verify the lexemes
        lexemes_by_lemma = Map.new(lexemes, &{&1.lemma, &1})

        assert Map.has_key?(lexemes_by_lemma, "test")
        assert Map.has_key?(lexemes_by_lemma, "sentence")
        assert Map.has_key?(lexemes_by_lemma, ".")

        # Count total tokens - should be 9 (3 tokens per chapter × 3 chapters)
        token_count = Repo.aggregate(Token, :count)
        assert token_count == 9

        # All tokens should point to the same lexemes
        tokens = Repo.all(from(t in Token, preload: :lexeme))

        # Group tokens by lexeme
        tokens_by_lexeme =
          Enum.group_by(tokens, & &1.lexeme.lemma)

        # Each lexeme should have 3 tokens (one per chapter)
        assert length(tokens_by_lexeme["test"]) == 3
        assert length(tokens_by_lexeme["sentence"]) == 3
        assert length(tokens_by_lexeme["."]) == 3
      after
        :meck.unload(Lex.Text.NLP)
      end
    end
  end
end
