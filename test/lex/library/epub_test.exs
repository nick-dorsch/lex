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

  describe "list_chapters/1" do
    test "returns chapters in reading order" do
      path = "test/fixtures/epubs/el_principito.epub"
      assert {:ok, chapters} = EPUB.list_chapters(path)

      assert length(chapters) == 1
      [chapter] = chapters
      assert chapter.id == "chapter1"
      assert chapter.title == "Chapter 1"
      assert chapter.href == "chapter1.xhtml"
      assert chapter.position == 1
    end

    test "excludes front and back matter (linear=no)" do
      path = "test/fixtures/epubs/multi_chapter.epub"
      assert {:ok, chapters} = EPUB.list_chapters(path)

      # Should only have 3 chapters, excluding copyright, dedication, and appendix
      assert length(chapters) == 3

      # Verify order and content
      [ch1, ch2, ch3] = chapters

      assert ch1.id == "chapter1"
      assert ch1.title == "Chapter 1"
      assert ch1.href == "chapter1.xhtml"
      assert ch1.position == 1

      assert ch2.id == "chapter2"
      assert ch2.title == "Chapter 2"
      assert ch2.href == "chapter2.xhtml"
      assert ch2.position == 2

      assert ch3.id == "chapter3"
      assert ch3.title == "Chapter 3"
      assert ch3.href == "chapter3.xhtml"
      assert ch3.position == 3
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} = EPUB.list_chapters("/path/to/nonexistent.epub")
    end

    test "returns error for invalid EPUB file" do
      # Create a temp file that's not a valid EPUB
      temp_file =
        Path.join(System.tmp_dir!(), "invalid_epub_#{:erlang.unique_integer([:positive])}.epub")

      File.write!(temp_file, "not a valid epub")

      assert {:error, :invalid_epub} = EPUB.list_chapters(temp_file)

      File.rm!(temp_file)
    end
  end
end
