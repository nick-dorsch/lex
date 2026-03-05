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

    test "parses language from fixture metadata" do
      path = "test/fixtures/epubs/no_language.epub"

      assert {:ok, metadata} = EPUB.parse_metadata(path)
      assert metadata.title == "Unknown Language Book"
      assert metadata.author == "Test Author"
      assert metadata.language == "es"
    end

    test "normalizes language codes to base language" do
      # Create an EPUB with regional language code
      temp_dir =
        Path.join(System.tmp_dir!(), "lex_lang_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      build_dir = Path.join(temp_dir, "lang_test")
      File.mkdir_p!(build_dir)

      File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

      meta_inf_dir = Path.join(build_dir, "META-INF")
      File.mkdir_p!(meta_inf_dir)

      container_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """

      File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

      oebps_dir = Path.join(build_dir, "OEBPS")
      File.mkdir_p!(oebps_dir)

      xhtml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>Test</title></head>
      <body>
        <p>Test content</p>
      </body>
      </html>
      """

      File.write!(Path.join(oebps_dir, "chapter.xhtml"), xhtml_content)

      # Create content.opf with regional language code
      opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Regional Language Test</dc:title>
          <dc:creator>Test</dc:creator>
          <dc:language>es-ES</dc:language>
          <dc:identifier id="bookid">urn:uuid:test-lang</dc:identifier>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """

      File.write!(Path.join(oebps_dir, "content.opf"), opf)

      epub_path = Path.join(temp_dir, "lang_test.epub")

      files = [
        {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
        {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
        {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
        {~c"OEBPS/chapter.xhtml", File.read!(Path.join(oebps_dir, "chapter.xhtml"))}
      ]

      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

      assert {:ok, metadata} = EPUB.parse_metadata(epub_path)
      assert metadata.language == "es"

      File.rm_rf!(temp_dir)
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

  describe "get_chapter_content/2" do
    test "successfully extracts text from El Principito chapter" do
      path = "test/fixtures/epubs/el_principito.epub"
      assert {:ok, content} = EPUB.get_chapter_content(path, "chapter1.xhtml")

      # Should contain the heading and paragraph text
      assert content =~ "Chapter 1"
      assert content =~ "Once upon a time"

      # Should not contain HTML tags
      refute content =~ "<h1>"
      refute content =~ "<p>"
      refute content =~ "</html>"
    end

    test "extracts text from multiple chapters" do
      path = "test/fixtures/epubs/multi_chapter.epub"

      # Test chapter 1
      assert {:ok, ch1} = EPUB.get_chapter_content(path, "chapter1.xhtml")
      assert ch1 =~ "Chapter 1"
      assert ch1 =~ "Once upon a time"

      # Test chapter 2
      assert {:ok, ch2} = EPUB.get_chapter_content(path, "chapter2.xhtml")
      assert ch2 =~ "Chapter 2"
      assert ch2 =~ "The story continues"

      # Test chapter 3
      assert {:ok, ch3} = EPUB.get_chapter_content(path, "chapter3.xhtml")
      assert ch3 =~ "Chapter 3"
      assert ch3 =~ "The end"
    end

    test "preserves paragraph structure with newlines between block elements" do
      path = "test/fixtures/epubs/multi_chapter.epub"
      assert {:ok, content} = EPUB.get_chapter_content(path, "chapter1.xhtml")

      # Block elements should be separated by newlines
      assert content =~ "Chapter 1"
      assert content =~ "Once upon a time"
      # Verify structure is preserved (h1 and p are on separate lines)
      assert content =~ "Chapter 1\n"
    end

    test "extracts heading tags as standalone text blocks" do
      path = "test/fixtures/epubs/multi_chapter.epub"
      assert {:ok, content} = EPUB.get_chapter_content(path, "chapter2.xhtml")

      assert content =~ "Chapter 2\n\nThe story continues..."
    end

    test "decodes HTML entities" do
      # Create an EPUB with HTML entities
      temp_dir =
        Path.join(System.tmp_dir!(), "lex_entity_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      build_dir = Path.join(temp_dir, "entity_test")
      File.mkdir_p!(build_dir)

      # Create mimetype
      File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

      # Create META-INF/container.xml
      meta_inf_dir = Path.join(build_dir, "META-INF")
      File.mkdir_p!(meta_inf_dir)

      container_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """

      File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

      # Create OEBPS directory
      oebps_dir = Path.join(build_dir, "OEBPS")
      File.mkdir_p!(oebps_dir)

      # Create chapter with HTML entities
      xhtml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>Test</title></head>
      <body>
        <p>AT&amp;T and 5 &lt; 10 &gt; 3 &quot;quoted&quot; &#39;apos&#39;</p>
      </body>
      </html>
      """

      File.write!(Path.join(oebps_dir, "chapter.xhtml"), xhtml_content)

      # Create content.opf
      opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Entity Test</dc:title>
          <dc:creator>Test</dc:creator>
          <dc:language>en</dc:language>
          <dc:identifier id="bookid">urn:uuid:test-entities</dc:identifier>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """

      File.write!(Path.join(oebps_dir, "content.opf"), opf)

      # Create the EPUB
      epub_path = Path.join(temp_dir, "entity_test.epub")

      files = [
        {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
        {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
        {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
        {~c"OEBPS/chapter.xhtml", File.read!(Path.join(oebps_dir, "chapter.xhtml"))}
      ]

      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

      # Test entity decoding
      assert {:ok, content} = EPUB.get_chapter_content(epub_path, "chapter.xhtml")
      assert content =~ "AT&T"
      assert content =~ "5 < 10 > 3"
      assert content =~ "\"quoted\""
      assert content =~ "'apos'"
      refute content =~ "&amp;"
      refute content =~ "&lt;"
      refute content =~ "&gt;"

      # Cleanup
      File.rm_rf!(temp_dir)
    end

    test "preserves UTF-8 characters in chapter content" do
      temp_dir =
        Path.join(System.tmp_dir!(), "lex_utf8_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      build_dir = Path.join(temp_dir, "utf8_test")
      File.mkdir_p!(build_dir)

      File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

      meta_inf_dir = Path.join(build_dir, "META-INF")
      File.mkdir_p!(meta_inf_dir)

      container_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """

      File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

      oebps_dir = Path.join(build_dir, "OEBPS")
      File.mkdir_p!(oebps_dir)

      xhtml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>Prueba UTF-8</title></head>
      <body>
        <p>¡Un día vi ponerse el sol cuarenta y tres veces!</p>
      </body>
      </html>
      """

      File.write!(Path.join(oebps_dir, "chapter.xhtml"), xhtml_content)

      opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>UTF-8 Test</dc:title>
          <dc:creator>Test</dc:creator>
          <dc:language>es</dc:language>
          <dc:identifier id="bookid">urn:uuid:test-utf8</dc:identifier>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """

      File.write!(Path.join(oebps_dir, "content.opf"), opf)

      epub_path = Path.join(temp_dir, "utf8_test.epub")

      files = [
        {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
        {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
        {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
        {~c"OEBPS/chapter.xhtml", File.read!(Path.join(oebps_dir, "chapter.xhtml"))}
      ]

      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

      assert {:ok, content} = EPUB.get_chapter_content(epub_path, "chapter.xhtml")
      assert content =~ "¡Un día vi ponerse el sol cuarenta y tres veces!"
      refute content =~ "Â¡"
      refute content =~ "dÃ"

      File.rm_rf!(temp_dir)
    end

    test "extracts only body text and excludes head metadata" do
      temp_dir =
        Path.join(System.tmp_dir!(), "lex_body_only_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      build_dir = Path.join(temp_dir, "body_only_test")
      File.mkdir_p!(build_dir)

      File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

      meta_inf_dir = Path.join(build_dir, "META-INF")
      File.mkdir_p!(meta_inf_dir)

      container_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """

      File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

      oebps_dir = Path.join(build_dir, "OEBPS")
      File.mkdir_p!(oebps_dir)

      xhtml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head>
        <title>9788494566110-7</title>
        <style>@page {padding: 0pt; margin:0pt} body { text-align: center; }</style>
      </head>
      <body>
        <p>Rió, tocó la cuerda e hizo mover la polea.</p>
      </body>
      </html>
      """

      File.write!(Path.join(oebps_dir, "chapter.xhtml"), xhtml_content)

      opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Body Test</dc:title>
          <dc:creator>Test</dc:creator>
          <dc:language>es</dc:language>
          <dc:identifier id="bookid">urn:uuid:test-body-only</dc:identifier>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """

      File.write!(Path.join(oebps_dir, "content.opf"), opf)

      epub_path = Path.join(temp_dir, "body_only_test.epub")

      files = [
        {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
        {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
        {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
        {~c"OEBPS/chapter.xhtml", File.read!(Path.join(oebps_dir, "chapter.xhtml"))}
      ]

      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

      assert {:ok, content} = EPUB.get_chapter_content(epub_path, "chapter.xhtml")
      assert content =~ "Rió, tocó la cuerda e hizo mover la polea."
      refute content =~ "9788494566110-7"
      refute content =~ "@page"

      File.rm_rf!(temp_dir)
    end

    test "decodes ISO-8859-1 chapter content using declared encoding" do
      temp_dir =
        Path.join(System.tmp_dir!(), "lex_latin1_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      build_dir = Path.join(temp_dir, "latin1_test")
      File.mkdir_p!(build_dir)

      File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

      meta_inf_dir = Path.join(build_dir, "META-INF")
      File.mkdir_p!(meta_inf_dir)

      container_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """

      File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

      oebps_dir = Path.join(build_dir, "OEBPS")
      File.mkdir_p!(oebps_dir)

      xhtml_latin1 =
        """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1"/></head>
        <body>
          <p>Página en español: ¡dónde está?</p>
        </body>
        </html>
        """
        |> :unicode.characters_to_binary(:utf8, :latin1)

      File.write!(Path.join(oebps_dir, "chapter.xhtml"), xhtml_latin1)

      opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Latin1 Test</dc:title>
          <dc:creator>Test</dc:creator>
          <dc:language>es</dc:language>
          <dc:identifier id="bookid">urn:uuid:test-latin1</dc:identifier>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """

      File.write!(Path.join(oebps_dir, "content.opf"), opf)

      epub_path = Path.join(temp_dir, "latin1_test.epub")

      files = [
        {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
        {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
        {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
        {~c"OEBPS/chapter.xhtml", File.read!(Path.join(oebps_dir, "chapter.xhtml"))}
      ]

      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

      assert {:ok, content} = EPUB.get_chapter_content(epub_path, "chapter.xhtml")
      assert content =~ "Página en español: ¡dónde está?"
      refute content =~ "PÃ¡gina"
      refute content =~ "dÃ³nde"

      File.rm_rf!(temp_dir)
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} =
               EPUB.get_chapter_content("/path/to/nonexistent.epub", "chapter.xhtml")
    end

    test "returns error for invalid EPUB file" do
      temp_file =
        Path.join(System.tmp_dir!(), "invalid_epub_#{:erlang.unique_integer([:positive])}.epub")

      File.write!(temp_file, "not a valid epub")

      assert {:error, :invalid_epub} = EPUB.get_chapter_content(temp_file, "chapter.xhtml")

      File.rm!(temp_file)
    end

    test "returns error for non-existent chapter" do
      path = "test/fixtures/epubs/el_principito.epub"
      assert {:error, :chapter_not_found} = EPUB.get_chapter_content(path, "nonexistent.xhtml")
    end

    test "handles empty chapters gracefully" do
      # Create an EPUB with an empty chapter
      temp_dir =
        Path.join(System.tmp_dir!(), "lex_empty_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      build_dir = Path.join(temp_dir, "empty_test")
      File.mkdir_p!(build_dir)

      # Create mimetype
      File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

      # Create META-INF/container.xml
      meta_inf_dir = Path.join(build_dir, "META-INF")
      File.mkdir_p!(meta_inf_dir)

      container_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """

      File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

      # Create OEBPS directory
      oebps_dir = Path.join(build_dir, "OEBPS")
      File.mkdir_p!(oebps_dir)

      # Create empty chapter (just HTML structure, no text content in body)
      xhtml_content = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title></title></head>
      <body>
      </body>
      </html>
      """

      File.write!(Path.join(oebps_dir, "empty.xhtml"), xhtml_content)

      # Create content.opf
      opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Empty Test</dc:title>
          <dc:creator>Test</dc:creator>
          <dc:language>en</dc:language>
          <dc:identifier id="bookid">urn:uuid:test-empty</dc:identifier>
        </metadata>
        <manifest>
          <item id="chapter1" href="empty.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """

      File.write!(Path.join(oebps_dir, "content.opf"), opf)

      # Create the EPUB
      epub_path = Path.join(temp_dir, "empty_test.epub")

      files = [
        {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
        {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
        {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
        {~c"OEBPS/empty.xhtml", File.read!(Path.join(oebps_dir, "empty.xhtml"))}
      ]

      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

      # Test empty chapter handling
      assert {:error, :empty_chapter} = EPUB.get_chapter_content(epub_path, "empty.xhtml")

      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end
end
