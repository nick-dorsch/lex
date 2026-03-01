defmodule Lex.Library.EPUBTest do
  use ExUnit.Case, async: true

  alias Lex.Library.EPUB

  describe "parse_metadata/1" do
    test "successfully parses El Principito metadata" do
      path = "test/fixtures/epubs/el_principito.epub"
      assert {:ok, metadata} = EPUB.parse_metadata(path)

      assert metadata.title == "El Principito"
      assert metadata.author == "Antoine de Saint-Exupéry"
      assert metadata.language == "es"
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} = EPUB.parse_metadata("/path/to/nonexistent.epub")
    end

    test "returns error for file without .epub extension" do
      assert {:error, :file_not_found} = EPUB.parse_metadata("/path/to/file.txt")
    end

    test "returns error for invalid ZIP file" do
      # Create a temp file that's not a valid EPUB
      temp_file =
        Path.join(System.tmp_dir!(), "invalid_epub_#{:erlang.unique_integer([:positive])}.epub")

      File.write!(temp_file, "not a valid epub")

      assert {:error, :invalid_epub} = EPUB.parse_metadata(temp_file)

      File.rm!(temp_file)
    end

    test "handles missing title with filename fallback" do
      path = "test/fixtures/epubs/no_title.epub"

      assert {:ok, metadata} = EPUB.parse_metadata(path)
      assert metadata.title == "no_title"
      assert metadata.author == "Anonymous"
    end

    test "handles missing author with Unknown fallback" do
      path = "test/fixtures/epubs/no_author.epub"

      assert {:ok, metadata} = EPUB.parse_metadata(path)
      assert metadata.title == "Unknown Author Book"
      assert metadata.author == "Unknown"
      assert metadata.language == "fr"
    end

    test "handles missing language with 'es' default" do
      path = "test/fixtures/epubs/no_language.epub"

      assert {:ok, metadata} = EPUB.parse_metadata(path)
      assert metadata.title == "Unknown Language Book"
      assert metadata.author == "Test Author"
      assert metadata.language == "es"
    end
  end
end
