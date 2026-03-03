defmodule Lex.LibraryTest do
  use Lex.DataCase, async: false

  import Ecto.Query

  alias Lex.Library
  alias Lex.Library.{Document, ImportTracker, Section}
  alias Lex.Repo
  alias Lex.Text.{Lexeme, Sentence, Token}
  alias Phoenix.PubSub

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

    test "returns validation error when user does not exist" do
      invalid_user_id = -1

      assert {:error, {:validation_failed, changeset}} =
               Library.import_epub("test/fixtures/epubs/el_principito.epub",
                 user_id: invalid_user_id
               )

      errors =
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)

      assert "does not exist" in errors.user_id
    end

    test "skips malformed NLP tokens and continues import", %{user: user} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:ok,
         [
           %{
             "position" => 1,
             "text" => "Hola ???.",
             "char_start" => 0,
             "char_end" => 9,
             "tokens" => [
               %{
                 "position" => 1,
                 "surface" => "Hola",
                 "normalized_surface" => "hola",
                 "lemma" => "hola",
                 "pos" => "INTJ",
                 "is_punctuation" => false,
                 "char_start" => 0,
                 "char_end" => 4
               },
               %{
                 "position" => 2,
                 "surface" => "   ",
                 "normalized_surface" => "",
                 "lemma" => nil,
                 "pos" => "X",
                 "is_punctuation" => false,
                 "char_start" => 5,
                 "char_end" => 8
               },
               %{
                 "position" => 3,
                 "surface" => ".",
                 "normalized_surface" => ".",
                 "lemma" => ".",
                 "pos" => "PUNCT",
                 "is_punctuation" => true,
                 "char_start" => 8,
                 "char_end" => 9
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"

        assert {:ok, document} = Library.import_epub(path, user_id: user.id)
        assert document.status == "ready"

        sections = Repo.all(from(s in Section, where: s.document_id == ^document.id))
        [section] = sections

        [sentence] = Repo.all(from(s in Sentence, where: s.section_id == ^section.id))

        tokens =
          Repo.all(from(t in Token, where: t.sentence_id == ^sentence.id, order_by: t.position))

        assert length(tokens) == 2
        assert Enum.at(tokens, 0).surface == "Hola"
        assert Enum.at(tokens, 1).surface == "."
      after
        :meck.unload(Lex.Text.NLP)
      end
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

  describe "calibre_library_path/0" do
    test "returns expanded default path" do
      path = Library.calibre_library_path()

      assert String.starts_with?(path, "/")
      assert path =~ "Calibre Library"
    end

    test "reads from env var CALIBRE_LIBRARY_PATH" do
      original_path = System.get_env("CALIBRE_LIBRARY_PATH")

      try do
        System.put_env("CALIBRE_LIBRARY_PATH", "/custom/calibre/path")
        Application.put_env(:lex, :calibre_library_path, "/custom/calibre/path")

        path = Library.calibre_library_path()
        assert path == "/custom/calibre/path"
      after
        if original_path do
          System.put_env("CALIBRE_LIBRARY_PATH", original_path)
        else
          System.delete_env("CALIBRE_LIBRARY_PATH")
        end

        Application.put_env(:lex, :calibre_library_path, "~/Calibre Library")
      end
    end

    test "expands ~ to home directory" do
      original_config = Application.fetch_env!(:lex, :calibre_library_path)

      try do
        Application.put_env(:lex, :calibre_library_path, "~/MyCalibre")

        path = Library.calibre_library_path()

        refute path =~ "~"
        assert String.starts_with?(path, "/")
        assert path =~ "MyCalibre"
      after
        Application.put_env(:lex, :calibre_library_path, original_config)
      end
    end
  end

  describe "import_epub_async/3" do
    setup do
      # Create a test user with unique email
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test_async#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      # Use unique file paths to avoid pollution
      file_path = "/tmp/test_async_#{System.unique_integer([:positive])}.epub"

      # Copy fixture file to temp location
      File.cp!("test/fixtures/epubs/el_principito.epub", file_path)

      on_exit(fn ->
        File.rm_rf(file_path)
        ImportTracker.reset_status(file_path)
      end)

      {:ok, user: user, file_path: file_path}
    end

    test "starts async import and returns :started", %{user: user, file_path: file_path} do
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
        assert {:ok, :started} = Library.import_epub_async(file_path, user.id)

        # Wait for the import to complete
        Process.sleep(200)

        # Verify ImportTracker was updated
        assert match?({:completed, _}, ImportTracker.get_status(file_path))

        # Verify document was created
        document = Repo.one!(from(d in Document, where: d.source_file == ^file_path))
        assert document.user_id == user.id
        assert document.status == "ready"
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "returns :already_importing when import already in progress", %{
      user: user,
      file_path: file_path
    } do
      # Manually mark as importing in tracker
      ImportTracker.start_import(file_path, user.id)

      assert {:ok, :already_importing} = Library.import_epub_async(file_path, user.id)
    end

    test "returns :already_imported when document exists", %{user: user} do
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
               }
             ]
           }
         ]}
      end)

      try do
        path = "test/fixtures/epubs/el_principito.epub"
        source_file = "/custom/source/path.epub"

        # First, import synchronously
        assert {:ok, _document} =
                 Library.import_epub(path, user_id: user.id, source_file: source_file)

        # Now try async import with same source_file
        assert {:ok, :already_imported} =
                 Library.import_epub_async(path, user.id, source_file: source_file)
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "handles import errors gracefully", %{user: user} do
      # Create a mock EPUB file path that doesn't exist
      nonexistent_file = "/nonexistent/path/book_#{System.unique_integer([:positive])}.epub"
      user_id = user.id

      topic = ImportTracker.topic(user_id)
      PubSub.subscribe(Lex.PubSub, topic)

      assert {:ok, :started} = Library.import_epub_async(nonexistent_file, user_id)

      # Wait for error broadcast
      assert_receive {:import_failed, ^nonexistent_file, _reason, ^user_id}, 1000

      # Verify tracker shows error state
      assert match?({:error, _}, ImportTracker.get_status(nonexistent_file))
    end

    test "broadcasts PubSub events on completion", %{user: user, file_path: file_path} do
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
               }
             ]
           }
         ]}
      end)

      try do
        user_id = user.id
        topic = ImportTracker.topic(user_id)
        PubSub.subscribe(Lex.PubSub, topic)

        assert {:ok, :started} = Library.import_epub_async(file_path, user_id)

        # Should receive started event
        assert_receive {:import_started, ^file_path, ^user_id}, 1000

        # Should receive at least one progress event
        assert_receive {:import_progress, ^file_path, percent, stage, ^user_id}, 2000
        assert is_integer(percent)
        assert percent >= 0 and percent <= 100
        assert is_binary(stage)

        # Should receive completed event
        assert_receive {:import_completed, ^file_path, document_id, ^user_id}, 2000
        assert is_integer(document_id)

        # Verify document was created
        document = Repo.get!(Document, document_id)
        assert document.user_id == user_id
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "handles concurrent import requests idempotently", %{user: user, file_path: file_path} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        # Add small delay to simulate processing
        Process.sleep(50)

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
               }
             ]
           }
         ]}
      end)

      try do
        # Start multiple concurrent async imports
        results =
          for _ <- 1..5 do
            Task.async(fn ->
              Library.import_epub_async(file_path, user.id)
            end)
          end
          |> Task.await_many(5000)

        # Only one should return :started, others should return :already_importing
        started_count = Enum.count(results, &(&1 == {:ok, :started}))
        already_importing_count = Enum.count(results, &(&1 == {:ok, :already_importing}))

        assert started_count == 1
        assert already_importing_count == 4

        # Wait for import to complete
        Process.sleep(300)

        # Verify only one document was created
        documents = Repo.all(from(d in Document, where: d.source_file == ^file_path))
        assert length(documents) == 1
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "uses source_file override when provided", %{user: user, file_path: file_path} do
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
               }
             ]
           }
         ]}
      end)

      try do
        source_file = "/custom/source/path_#{System.unique_integer([:positive])}.epub"

        assert {:ok, :started} =
                 Library.import_epub_async(file_path, user.id, source_file: source_file)

        Process.sleep(200)

        # Verify document was created with the override path
        document = Repo.one!(from(d in Document, where: d.source_file == ^source_file))
        assert document.user_id == user.id
      after
        :meck.unload(Lex.Text.NLP)
      end
    end
  end
end
