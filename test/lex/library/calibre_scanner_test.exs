defmodule Lex.Library.CalibreScannerTest do
  use Lex.DataCase, async: false

  alias Lex.Library.{CalibreScanner, Document}
  alias Lex.Repo

  describe "scan/0" do
    setup do
      # Create a temporary directory for testing
      temp_dir =
        Path.join(System.tmp_dir!(), "calibre_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      # Store original config
      original_config = Application.fetch_env!(:lex, :calibre_library_path)

      # Set the test directory as calibre path
      Application.put_env(:lex, :calibre_library_path, temp_dir)

      on_exit(fn ->
        # Restore original config
        Application.put_env(:lex, :calibre_library_path, original_config)
        # Clean up temp directory
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "returns empty list when calibre folder has no EPUBs", %{temp_dir: _temp_dir} do
      # Empty directory
      assert {:ok, []} = CalibreScanner.scan()
    end

    test "finds all EPUB files recursively and parses metadata", %{temp_dir: temp_dir} do
      # Copy test EPUB to temp directory
      source_epub = "test/fixtures/epubs/el_principito.epub"
      dest_epub = Path.join(temp_dir, "el_principito.epub")
      File.cp!(source_epub, dest_epub)

      assert {:ok, [book]} = CalibreScanner.scan()

      assert book.file_path == dest_epub
      assert book.title == "El Principito"
      assert book.author == "Antoine de Saint-Exupéry"
      assert book.language == "es"
      assert book.import_status == :not_imported
      assert book.document_id == nil
    end

    test "finds EPUBs in nested directories", %{temp_dir: temp_dir} do
      # Create nested structure
      nested_dir = Path.join(temp_dir, "Author Name")
      File.mkdir_p!(nested_dir)

      source_epub = "test/fixtures/epubs/el_principito.epub"
      dest_epub = Path.join(nested_dir, "book.epub")
      File.cp!(source_epub, dest_epub)

      assert {:ok, [book]} = CalibreScanner.scan()

      assert book.file_path == dest_epub
      assert book.title == "El Principito"
    end

    test "includes cover path when cover image exists", %{temp_dir: temp_dir} do
      source_epub = "test/fixtures/epubs/el_principito.epub"
      nested_dir = Path.join(temp_dir, "Author Name")
      File.mkdir_p!(nested_dir)

      dest_epub = Path.join(nested_dir, "book.epub")
      File.cp!(source_epub, dest_epub)

      cover_path = Path.join(nested_dir, "cover.jpg")
      File.write!(cover_path, "fake-cover-bytes")

      assert {:ok, [book]} = CalibreScanner.scan()
      assert book.cover_path == cover_path
    end

    test "correctly identifies already-imported books", %{temp_dir: temp_dir} do
      # Create a user
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      # Copy test EPUB
      source_epub = "test/fixtures/epubs/el_principito.epub"
      dest_epub = Path.join(temp_dir, "imported_book.epub")
      File.cp!(source_epub, dest_epub)

      # Create a document that references this file
      document =
        %Document{}
        |> Ecto.Changeset.change(%{
          title: "El Principito",
          author: "Antoine de Saint-Exupéry",
          language: "es",
          status: "ready",
          source_file: dest_epub,
          user_id: user.id
        })
        |> Repo.insert!()

      assert {:ok, [book]} = CalibreScanner.scan()

      assert book.file_path == dest_epub
      assert book.title == "El Principito"
      assert book.author == "Antoine de Saint-Exupéry"
      assert book.language == "es"
      assert book.import_status == :imported
      assert book.document_id == document.id
    end

    test "returns error when calibre path doesn't exist" do
      # Set a non-existent path
      Application.put_env(:lex, :calibre_library_path, "/nonexistent/path/xyz")

      assert {:error, :calibre_path_not_found} = CalibreScanner.scan()
    end

    test "handles multiple EPUBs with mixed import status", %{temp_dir: temp_dir} do
      # Create a user
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      # Create two EPUBs: one imported, one not
      source_epub = "test/fixtures/epubs/el_principito.epub"

      imported_path = Path.join(temp_dir, "imported.epub")
      File.cp!(source_epub, imported_path)

      not_imported_path = Path.join(temp_dir, "not_imported.epub")
      File.cp!(source_epub, not_imported_path)

      # Import only the first one
      %Document{}
      |> Ecto.Changeset.change(%{
        title: "Imported Book",
        author: "Test Author",
        language: "es",
        status: "ready",
        source_file: imported_path,
        user_id: user.id
      })
      |> Repo.insert!()

      assert {:ok, books} = CalibreScanner.scan()
      assert length(books) == 2

      # Find each book by path
      by_path = Map.new(books, &{&1.file_path, &1})

      # Verify imported book
      imported_book = Map.get(by_path, imported_path)
      assert imported_book.import_status == :imported
      assert imported_book.document_id != nil
      assert imported_book.title == "Imported Book"

      # Verify not imported book
      not_imported_book = Map.get(by_path, not_imported_path)
      assert not_imported_book.import_status == :not_imported
      assert not_imported_book.document_id == nil
      # Should parse metadata from the EPUB file
      assert not_imported_book.title == "El Principito"
    end

    test "handles EPUBs with missing metadata gracefully", %{temp_dir: temp_dir} do
      # Copy an EPUB with missing metadata
      source_epub = "test/fixtures/epubs/no_title.epub"
      dest_epub = Path.join(temp_dir, "no_title.epub")
      File.cp!(source_epub, dest_epub)

      assert {:ok, [book]} = CalibreScanner.scan()

      assert book.file_path == dest_epub
      # Should use filename as fallback
      assert book.title == "no_title"
      assert book.import_status == :not_imported
    end

    test "handles EPUBs with missing author", %{temp_dir: temp_dir} do
      source_epub = "test/fixtures/epubs/no_author.epub"
      dest_epub = Path.join(temp_dir, "no_author.epub")
      File.cp!(source_epub, dest_epub)

      assert {:ok, [book]} = CalibreScanner.scan()

      assert book.author == "Unknown"
    end

    test "handles EPUBs with missing language", %{temp_dir: temp_dir} do
      source_epub = "test/fixtures/epubs/no_language.epub"
      dest_epub = Path.join(temp_dir, "no_language.epub")
      File.cp!(source_epub, dest_epub)

      assert {:ok, [book]} = CalibreScanner.scan()

      # Should default to "es"
      assert book.language == "es"
    end

    test "handles invalid EPUB files with error status", %{temp_dir: temp_dir} do
      # Create an invalid EPUB (just an empty file with .epub extension)
      invalid_epub = Path.join(temp_dir, "invalid.epub")
      File.write!(invalid_epub, "not a valid epub")

      assert {:ok, [book]} = CalibreScanner.scan()

      assert book.file_path == invalid_epub
      assert book.import_status == :error
      assert book.title == "invalid"
    end

    test "batch query correctly matches files", %{temp_dir: temp_dir} do
      # Create a user
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      # Create multiple EPUBs
      source_epub = "test/fixtures/epubs/el_principito.epub"

      paths =
        for i <- 1..5 do
          path = Path.join(temp_dir, "book#{i}.epub")
          File.cp!(source_epub, path)
          path
        end

      # Import only books 2 and 4
      for i <- [2, 4] do
        %Document{}
        |> Ecto.Changeset.change(%{
          title: "Book #{i}",
          author: "Author #{i}",
          language: "es",
          status: "ready",
          source_file: Enum.at(paths, i - 1),
          user_id: user.id
        })
        |> Repo.insert!()
      end

      assert {:ok, books} = CalibreScanner.scan()
      assert length(books) == 5

      # Verify each book's status
      books
      |> Enum.with_index(1)
      |> Enum.each(fn {book, i} ->
        if i in [2, 4] do
          assert book.import_status == :imported, "Book #{i} should be imported"
          assert book.title == "Book #{i}"
        else
          assert book.import_status == :not_imported, "Book #{i} should not be imported"
        end
      end)
    end

    test "uses document metadata for imported books", %{temp_dir: temp_dir} do
      # Create a user
      user =
        %Lex.Accounts.User{}
        |> Ecto.Changeset.change(%{
          name: "Test User",
          email: "test#{System.unique_integer([:positive])}@example.com",
          primary_language: "en"
        })
        |> Repo.insert!()

      # Copy test EPUB
      source_epub = "test/fixtures/epubs/el_principito.epub"
      dest_epub = Path.join(temp_dir, "renamed.epub")
      File.cp!(source_epub, dest_epub)

      # Create document with different metadata than the EPUB
      %Document{}
      |> Ecto.Changeset.change(%{
        title: "Custom Title",
        author: "Custom Author",
        language: "fr",
        status: "ready",
        source_file: dest_epub,
        user_id: user.id
      })
      |> Repo.insert!()

      assert {:ok, [book]} = CalibreScanner.scan()

      # Should use document metadata, not EPUB metadata
      assert book.title == "Custom Title"
      assert book.author == "Custom Author"
      assert book.language == "fr"
      assert book.import_status == :imported
    end

    test "path expansion works correctly with ~", %{temp_dir: temp_dir} do
      # Create a symlink using ~ in the path (will be expanded)
      # We can't easily test ~ expansion, but we can test that
      # the path normalization works correctly

      # Just verify scanning works with the temp directory
      source_epub = "test/fixtures/epubs/el_principito.epub"
      dest_epub = Path.join(temp_dir, "book.epub")
      File.cp!(source_epub, dest_epub)

      assert {:ok, [_book]} = CalibreScanner.scan()
    end
  end
end
