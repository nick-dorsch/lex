defmodule Lex.Library.ImportWorkerTest do
  use Lex.DataCase, async: false

  alias Lex.Library.{Document, ImportTracker, ImportWorker}
  alias Lex.Repo

  describe "run/3" do
    setup do
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test_worker#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      file_path = "/tmp/test_worker_#{System.unique_integer([:positive])}.epub"
      File.cp!("test/fixtures/epubs/el_principito.epub", file_path)

      on_exit(fn ->
        File.rm_rf(file_path)
        ImportTracker.reset_status(file_path)
      end)

      {:ok, user: user, file_path: file_path}
    end

    test "successfully imports EPUB and marks as completed", %{user: user, file_path: file_path} do
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
        # Pre-mark as started (as import_epub_async would do)
        ImportTracker.start_import(file_path, user.id)

        # Run the worker
        assert :ok = ImportWorker.run(file_path, user.id, [])

        # Verify tracker shows completed
        assert {:completed, document_id} = ImportTracker.get_status(file_path)

        # Verify document exists
        document = Repo.get!(Document, document_id)
        assert document.user_id == user.id
        assert document.status == "ready"
        assert document.source_file == file_path
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "marks import as failed on EPUB parse error", %{user: user} do
      nonexistent_file = "/nonexistent/path/book_#{System.unique_integer([:positive])}.epub"

      on_exit(fn ->
        ImportTracker.reset_status(nonexistent_file)
      end)

      # Pre-mark as started
      ImportTracker.start_import(nonexistent_file, user.id)

      # Run the worker
      assert :ok = ImportWorker.run(nonexistent_file, user.id, [])

      # Verify tracker shows error
      assert {:error, error_message} = ImportTracker.get_status(nonexistent_file)
      assert error_message =~ "EPUB parsing failed"
    end

    test "marks import as failed on NLP error", %{user: user, file_path: file_path} do
      :meck.new(Lex.Text.NLP, [:passthrough])

      :meck.expect(Lex.Text.NLP, :process_text, fn _text, _opts ->
        {:error, :python_not_found}
      end)

      try do
        # Pre-mark as started
        ImportTracker.start_import(file_path, user.id)

        # Run the worker
        assert :ok = ImportWorker.run(file_path, user.id, [])

        # Verify tracker shows error
        assert {:error, error_message} = ImportTracker.get_status(file_path)
        assert error_message =~ "NLP processing failed"
      after
        :meck.unload(Lex.Text.NLP)
      end
    end

    test "uses source_file override option", %{user: user, file_path: file_path} do
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

        # Pre-mark as started
        ImportTracker.start_import(file_path, user.id)

        # Run the worker with override
        assert :ok = ImportWorker.run(file_path, user.id, source_file: source_file)

        # Verify document was created with override path
        assert {:completed, document_id} = ImportTracker.get_status(file_path)
        document = Repo.get!(Document, document_id)
        assert document.source_file == source_file
      after
        :meck.unload(Lex.Text.NLP)
      end
    end
  end
end
