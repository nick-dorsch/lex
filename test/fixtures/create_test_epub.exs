# Script to create test EPUB fixtures
# Run with: mix run test/fixtures/create_test_epub.exs

fixtures_dir = Path.expand("test/fixtures/epubs", "/home/nick/repos/lex")
File.mkdir_p!(fixtures_dir)
IO.puts("Fixtures directory: #{fixtures_dir}")

# Create a temp directory for building EPUBs
temp_dir = Path.join(System.tmp_dir!(), "lex_epub_build_#{:erlang.unique_integer([:positive])}")
File.mkdir_p!(temp_dir)
IO.puts("Temp directory: #{temp_dir}")

# Helper to escape XML special characters
escape_xml = fn text ->
  text
  |> String.replace("&", "&amp;")
  |> String.replace("<", "&lt;")
  |> String.replace(">", "&gt;")
  |> String.replace("\"", "&quot;")
  |> String.replace("'", "&apos;")
end

# Helper function to create EPUB with given metadata
create_epub = fn metadata, filename, escape_fn ->
  build_dir = Path.join(temp_dir, filename)
  File.mkdir_p!(build_dir)

  # Create mimetype (must be first and uncompressed)
  File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

  # Create META-INF/container.xml
  meta_inf_dir = Path.join(build_dir, "META-INF")
  File.mkdir_p!(meta_inf_dir)

  container_xml =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" <>
      "  <rootfiles>\n" <>
      "    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n" <>
      "  </rootfiles>\n" <>
      "</container>"

  File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

  # Create OEBPS directory
  oebps_dir = Path.join(build_dir, "OEBPS")
  File.mkdir_p!(oebps_dir)

  # Create a simple content page
  xhtml_content =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<!DOCTYPE html>\n" <>
      "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n" <>
      "<head>\n" <>
      "  <title>Chapter 1</title>\n" <>
      "</head>\n" <>
      "<body>\n" <>
      "  <h1>Chapter 1</h1>\n" <>
      "  <p>Once upon a time...</p>\n" <>
      "</body>\n" <>
      "</html>"

  File.write!(Path.join(oebps_dir, "chapter1.xhtml"), xhtml_content)

  # Create content.opf
  title = metadata[:title] || ""
  creator = metadata[:creator] || ""
  language = metadata[:language] || "es"
  identifier = metadata[:identifier] || "urn:uuid:#{:erlang.unique_integer([:positive])}"

  # Build metadata section conditionally
  title_element = if title != "", do: "    <dc:title>#{escape_fn.(title)}</dc:title>\n", else: ""

  creator_element =
    if creator != "", do: "    <dc:creator>#{escape_fn.(creator)}</dc:creator>\n", else: ""

  opf =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<package version=\"3.0\" xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"bookid\">\n" <>
      "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" <>
      title_element <>
      creator_element <>
      "    <dc:language>#{language}</dc:language>\n" <>
      "    <dc:identifier id=\"bookid\">#{identifier}</dc:identifier>\n" <>
      "    <meta property=\"dcterms:modified\">#{DateTime.utc_now() |> DateTime.to_iso8601()}</meta>\n" <>
      "  </metadata>\n" <>
      "  <manifest>\n" <>
      "    <item id=\"chapter1\" href=\"chapter1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "  </manifest>\n" <>
      "  <spine>\n" <>
      "    <itemref idref=\"chapter1\"/>\n" <>
      "  </spine>\n" <>
      "</package>"

  File.write!(Path.join(oebps_dir, "content.opf"), opf)

  # Create the EPUB ZIP file
  epub_path = Path.join(fixtures_dir, "#{filename}.epub")

  # Create list of files to zip
  files = [
    {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
    {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
    {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
    {~c"OEBPS/chapter1.xhtml", File.read!(Path.join(oebps_dir, "chapter1.xhtml"))}
  ]

  :zip.create(String.to_charlist(epub_path), files, compress: [~c".xhtml", ~c".opf", ~c".xml"])

  IO.puts("Created: #{epub_path}")
end

# Helper function to create EPUB with multiple chapters including front/back matter
create_multi_chapter_epub = fn filename, escape_fn ->
  build_dir = Path.join(temp_dir, filename)
  File.mkdir_p!(build_dir)

  # Create mimetype (must be first and uncompressed)
  File.write!(Path.join(build_dir, "mimetype"), "application/epub+zip")

  # Create META-INF/container.xml
  meta_inf_dir = Path.join(build_dir, "META-INF")
  File.mkdir_p!(meta_inf_dir)

  container_xml =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n" <>
      "  <rootfiles>\n" <>
      "    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n" <>
      "  </rootfiles>\n" <>
      "</container>"

  File.write!(Path.join(meta_inf_dir, "container.xml"), container_xml)

  # Create OEBPS directory
  oebps_dir = Path.join(build_dir, "OEBPS")
  File.mkdir_p!(oebps_dir)

  # Create content pages
  pages = [
    %{
      id: "copyright",
      href: "copyright.xhtml",
      title: "Copyright",
      content: "<h1>Copyright</h1><p>All rights reserved.</p>"
    },
    %{
      id: "dedication",
      href: "dedication.xhtml",
      title: "Dedication",
      content: "<h1>Dedication</h1><p>To my readers.</p>"
    },
    %{
      id: "chapter1",
      href: "chapter1.xhtml",
      title: "Chapter 1",
      content: "<h1>Chapter 1</h1><p>Once upon a time...</p>"
    },
    %{
      id: "chapter2",
      href: "chapter2.xhtml",
      title: "Chapter 2",
      content: "<h1>Chapter 2</h1><p>The story continues...</p>"
    },
    %{
      id: "chapter3",
      href: "chapter3.xhtml",
      title: "Chapter 3",
      content: "<h1>Chapter 3</h1><p>The end...</p>"
    },
    %{
      id: "appendix",
      href: "appendix.xhtml",
      title: "Appendix",
      content: "<h1>Appendix</h1><p>Additional notes.</p>"
    }
  ]

  # Write all page files
  Enum.each(pages, fn page ->
    xhtml =
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
        "<!DOCTYPE html>\n" <>
        "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n" <>
        "<head>\n" <>
        "  <title>#{page.title}</title>\n" <>
        "</head>\n" <>
        "<body>\n" <>
        "  #{page.content}\n" <>
        "</body>\n" <>
        "</html>"

    File.write!(Path.join(oebps_dir, page.href), xhtml)
  end)

  # Create content.opf
  opf =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<package version=\"3.0\" xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"bookid\">\n" <>
      "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n" <>
      "    <dc:title>#{filename}</dc:title>\n" <>
      "    <dc:creator>Test Author</dc:creator>\n" <>
      "    <dc:language>en</dc:language>\n" <>
      "    <dc:identifier id=\"bookid\">urn:uuid:test-multiple-chapters</dc:identifier>\n" <>
      "    <meta property=\"dcterms:modified\">#{DateTime.utc_now() |> DateTime.to_iso8601()}</meta>\n" <>
      "  </metadata>\n" <>
      "  <manifest>\n" <>
      "    <item id=\"copyright\" href=\"copyright.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "    <item id=\"dedication\" href=\"dedication.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "    <item id=\"chapter1\" href=\"chapter1.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "    <item id=\"chapter2\" href=\"chapter2.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "    <item id=\"chapter3\" href=\"chapter3.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "    <item id=\"appendix\" href=\"appendix.xhtml\" media-type=\"application/xhtml+xml\"/>\n" <>
      "  </manifest>\n" <>
      "  <spine>\n" <>
      "    <itemref idref=\"copyright\" linear=\"no\"/>\n" <>
      "    <itemref idref=\"dedication\" linear=\"no\"/>\n" <>
      "    <itemref idref=\"chapter1\"/>\n" <>
      "    <itemref idref=\"chapter2\"/>\n" <>
      "    <itemref idref=\"chapter3\"/>\n" <>
      "    <itemref idref=\"appendix\" linear=\"no\"/>\n" <>
      "  </spine>\n" <>
      "</package>"

  File.write!(Path.join(oebps_dir, "content.opf"), opf)

  # Create the EPUB ZIP file
  epub_path = Path.join(fixtures_dir, "#{filename}.epub")

  # Create list of files to zip
  files =
    [
      {~c"mimetype", File.read!(Path.join(build_dir, "mimetype"))},
      {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
      {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))}
    ] ++
      Enum.map(pages, fn page ->
        {~c"OEBPS/#{page.href}", File.read!(Path.join(oebps_dir, page.href))}
      end)

  :zip.create(String.to_charlist(epub_path), files, compress: [~c".xhtml", ~c".opf", ~c".xml"])

  IO.puts("Created: #{epub_path}")
end

# Create El Principito EPUB
create_epub.(
  %{
    title: "El Principito",
    creator: "Antoine de Saint-Exupéry",
    language: "es",
    identifier: "urn:isbn:9780156012195"
  },
  "el_principito",
  escape_xml
)

# Create EPUB with missing title
create_epub.(
  %{
    title: nil,
    creator: "Anonymous",
    language: "en",
    identifier: "urn:uuid:test-notitle"
  },
  "no_title",
  escape_xml
)

# Create EPUB with missing author
create_epub.(
  %{
    title: "Unknown Author Book",
    creator: nil,
    language: "fr",
    identifier: "urn:uuid:test-noauthor"
  },
  "no_author",
  escape_xml
)

# Create EPUB with missing language
create_epub.(
  %{
    title: "Unknown Language Book",
    creator: "Test Author",
    language: nil,
    identifier: "urn:uuid:test-nolang"
  },
  "no_language",
  escape_xml
)

# Create multi-chapter EPUB with front/back matter
create_multi_chapter_epub.("multi_chapter", escape_xml)

# Cleanup temp directory
File.rm_rf!(temp_dir)

# Verify files were created
IO.puts("\nVerifying created files:")
fixtures_dir |> File.ls!() |> Enum.each(&IO.puts("  - #{&1}"))

IO.puts("\nAll test EPUB fixtures created successfully!")
