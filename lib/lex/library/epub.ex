defmodule Lex.Library.EPUB do
  @moduledoc """
  EPUB parsing functionality for extracting metadata and content.
  """

  require Logger

  @mojibake_markers ["Ã", "Â", "â€", "â€“", "â€”", "â€œ", "â€", "â€˜", "â€™", "â€¦"]

  @doc """
  Parses metadata from an EPUB file.

  Returns `{:ok, %{title: string, author: string, language: string}}` on success,
  or `{:error, reason}` on failure.

  ## Error cases
  - `{:error, :file_not_found}` - File does not exist
  - `{:error, :invalid_epub}` - Not a valid ZIP/EPUB file
  - `{:error, :missing_opf}` - OPF package file is missing or invalid
  """
  @spec parse_metadata(Path.t()) ::
          {:ok, %{title: String.t(), author: String.t(), language: String.t()}}
          | {:error, atom()}
  def parse_metadata(path) do
    with :ok <- check_file_exists(path),
         {:ok, config} <- parse_epub(path) do
      metadata = extract_metadata(config, path)
      {:ok, metadata}
    end
  end

  defp check_file_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :file_not_found}
    end
  end

  defp parse_epub(path) do
    {:ok, BUPE.parse(path)}
  rescue
    e in ArgumentError ->
      if e.message =~ "does not exists" or e.message =~ "does not have an '.epub' extension" do
        {:error, :file_not_found}
      else
        {:error, :invalid_epub}
      end

    e in RuntimeError ->
      cond do
        e.message =~ "invalid mimetype" -> {:error, :invalid_epub}
        e.message =~ "rootfile" -> {:error, :missing_opf}
        true -> {:error, :invalid_epub}
      end

    _ ->
      {:error, :invalid_epub}
  end

  defp extract_metadata(%BUPE.Config{} = config, path) do
    title =
      case config.title do
        nil ->
          filename = Path.basename(path, ".epub")
          Logger.warning("EPUB missing title, using filename fallback: #{filename}")
          filename

        "" ->
          filename = Path.basename(path, ".epub")
          Logger.warning("EPUB missing title, using filename fallback: #{filename}")
          filename

        t ->
          t
      end

    author =
      case config.creator do
        nil -> "Unknown"
        "" -> "Unknown"
        c -> c
      end

    language =
      case config.language do
        nil -> "es"
        "" -> "es"
        l -> l
      end

    %{title: title, author: author, language: language}
  end

  @doc """
  Lists all chapters from an EPUB in reading order, excluding front/back matter.

  Returns `{:ok, [%{id: string, title: string, href: string, position: integer}]}` on success,
  or `{:error, reason}` on failure.

  Chapters are ordered according to the spine (reading order) and filtered to exclude
  items marked with `linear="no"` (front matter, back matter, etc.).

  ## Error cases
  - `{:error, :file_not_found}` - File does not exist
  - `{:error, :invalid_epub}` - Not a valid ZIP/EPUB file
  - `{:error, :missing_opf}` - OPF package file is missing or invalid
  """
  @spec list_chapters(Path.t()) ::
          {:ok, [%{id: String.t(), title: String.t(), href: String.t(), position: integer()}]}
          | {:error, atom()}
  def list_chapters(path) do
    with :ok <- check_file_exists(path),
         {:ok, config} <- parse_epub(path) do
      chapters = extract_chapters(config)
      {:ok, chapters}
    end
  end

  defp extract_chapters(%BUPE.Config{} = config) do
    # Build a map of manifest items by id for quick lookup
    manifest_by_id =
      config.pages
      |> List.wrap()
      |> Map.new(fn %BUPE.Item{} = item -> {item.id, item} end)

    # Get spine items (reading order), filter out non-linear items
    config.nav
    |> List.wrap()
    |> Enum.filter(fn itemref -> Map.get(itemref, :linear) != "no" end)
    |> Enum.with_index(1)
    |> Enum.map(fn {itemref, position} ->
      idref = Map.get(itemref, :idref)
      manifest_item = Map.get(manifest_by_id, idref)

      if manifest_item do
        %{
          id: manifest_item.id,
          title: derive_title(manifest_item),
          href: manifest_item.href,
          position: position
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp derive_title(%BUPE.Item{} = item) do
    # Use description from Item if available, otherwise derive from href
    case item.description do
      nil -> derive_title_from_href(item.href)
      "" -> derive_title_from_href(item.href)
      desc -> desc
    end
  end

  defp derive_title_from_href(href) do
    href
    |> Path.basename()
    |> Path.rootname()
    # Insert space between lowercase and uppercase letters (e.g., "chapter1" -> "chapter 1")
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    # Insert space between letters and numbers (e.g., "chapter1" -> "chapter 1")
    |> String.replace(~r/([a-zA-Z])(\d)/, "\\1 \\2")
    |> String.replace(~r/(\d)([a-zA-Z])/, "\\1 \\2")
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Extracts plain text content from a specific chapter in an EPUB file.

  Takes an EPUB file path and a chapter href (from `list_chapters/1`) and returns
  the chapter content as plain text with HTML tags stripped.

  ## Text Processing
  - Strips all HTML tags
  - Converts `<p>`, `<br>`, `<div>` block elements to newlines
  - Decodes HTML entities (&amp; → &, etc.)
  - Collapses multiple newlines to double newline (paragraph break)
  - Trims leading/trailing whitespace

  ## Return
  - `{:ok, plain_text_string}` on success
  - `{:error, :file_not_found}` - File does not exist
  - `{:error, :invalid_epub}` - Not a valid ZIP/EPUB file
  - `{:error, :chapter_not_found}` - Chapter href not found in EPUB
  - `{:error, :empty_chapter}` - Chapter file exists but contains no text

  ## Examples
      iex> EPUB.get_chapter_content("book.epub", "chapter1.xhtml")
      {:ok, "Chapter 1\\n\\nOnce upon a time..."}
  """
  @spec get_chapter_content(Path.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def get_chapter_content(path, href) do
    with :ok <- check_file_exists(path),
         {:ok, html_content} <- read_chapter_from_zip(path, href) do
      plain_text = html_to_plain_text(html_content)

      if plain_text == "" do
        {:error, :empty_chapter}
      else
        {:ok, plain_text}
      end
    end
  end

  defp read_chapter_from_zip(path, href) do
    case :zip.zip_open(String.to_charlist(path), [:memory]) do
      {:ok, zip_handle} ->
        try do
          # Try to find the chapter with the exact href
          case :zip.zip_get(String.to_charlist(href), zip_handle) do
            {:ok, {_, content}} when is_binary(content) ->
              {:ok, content}

            {:ok, {_, content}} when is_list(content) ->
              {:ok, :erlang.list_to_binary(content)}

            {:error, _} ->
              # Try with OEBPS/ prefix (common EPUB structure)
              case :zip.zip_get(String.to_charlist("OEBPS/#{href}"), zip_handle) do
                {:ok, {_, content}} when is_binary(content) ->
                  {:ok, content}

                {:ok, {_, content}} when is_list(content) ->
                  {:ok, :erlang.list_to_binary(content)}

                {:error, _} ->
                  # Try with OPS/ prefix (alternative EPUB structure)
                  case :zip.zip_get(String.to_charlist("OPS/#{href}"), zip_handle) do
                    {:ok, {_, content}} when is_binary(content) ->
                      {:ok, content}

                    {:ok, {_, content}} when is_list(content) ->
                      {:ok, :erlang.list_to_binary(content)}

                    {:error, _} ->
                      {:error, :chapter_not_found}
                  end
              end
          end
        after
          :zip.zip_close(zip_handle)
        end

      {:error, _} ->
        {:error, :invalid_epub}
    end
  end

  defp html_to_plain_text(html) do
    html
    |> decode_document_content()
    |> Floki.parse_fragment!()
    |> extract_body_text_with_newlines()
    |> decode_html_entities()
    |> cleanup_noise_lines()
    |> normalize_newlines()
    |> maybe_repair_mojibake()
    |> String.trim()
  end

  defp decode_document_content(content) when is_binary(content) do
    declared_encoding = detect_declared_encoding(content)

    decode_order =
      [declared_encoding, :utf8, :windows_1252, :latin1]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    decoded =
      Enum.find_value(decode_order, fn encoding ->
        case decode_content_with_encoding(content, encoding) do
          {:ok, text} when is_binary(text) -> text
          _ -> nil
        end
      end)

    decoded || content
  end

  defp detect_declared_encoding(content) do
    sample =
      content
      |> binary_part(0, min(byte_size(content), 2048))
      |> :unicode.characters_to_binary(:latin1, :utf8)

    case Regex.run(~r/encoding=["']([^"']+)["']/i, sample, capture: :all_but_first) do
      [encoding] -> normalize_encoding_name(encoding)
      _ -> detect_meta_charset(sample)
    end
  end

  defp detect_meta_charset(sample) do
    case Regex.run(~r/charset=([a-zA-Z0-9._-]+)/i, sample, capture: :all_but_first) do
      [encoding] -> normalize_encoding_name(encoding)
      _ -> nil
    end
  end

  defp normalize_encoding_name(name) do
    name
    |> String.downcase()
    |> String.trim()
    |> case do
      "utf-8" -> :utf8
      "utf8" -> :utf8
      "iso-8859-1" -> :latin1
      "iso8859-1" -> :latin1
      "latin1" -> :latin1
      "latin-1" -> :latin1
      "windows-1252" -> :windows_1252
      "cp1252" -> :windows_1252
      _ -> nil
    end
  end

  defp decode_content_with_encoding(content, :utf8) do
    if String.valid?(content), do: {:ok, content}, else: :error
  end

  defp decode_content_with_encoding(content, :latin1) do
    {:ok, :unicode.characters_to_binary(content, :latin1, :utf8)}
  rescue
    _ -> :error
  end

  defp decode_content_with_encoding(content, :windows_1252) do
    {:ok, windows_1252_to_utf8(content)}
  rescue
    _ -> :error
  end

  defp decode_content_with_encoding(_content, _encoding), do: :error

  defp windows_1252_to_utf8(content) do
    content
    |> :binary.bin_to_list()
    |> Enum.map(&windows_1252_codepoint/1)
    |> :unicode.characters_to_binary(:unicode, :utf8)
  end

  defp windows_1252_codepoint(0x80), do: 0x20AC
  defp windows_1252_codepoint(0x82), do: 0x201A
  defp windows_1252_codepoint(0x83), do: 0x0192
  defp windows_1252_codepoint(0x84), do: 0x201E
  defp windows_1252_codepoint(0x85), do: 0x2026
  defp windows_1252_codepoint(0x86), do: 0x2020
  defp windows_1252_codepoint(0x87), do: 0x2021
  defp windows_1252_codepoint(0x88), do: 0x02C6
  defp windows_1252_codepoint(0x89), do: 0x2030
  defp windows_1252_codepoint(0x8A), do: 0x0160
  defp windows_1252_codepoint(0x8B), do: 0x2039
  defp windows_1252_codepoint(0x8C), do: 0x0152
  defp windows_1252_codepoint(0x8E), do: 0x017D
  defp windows_1252_codepoint(0x91), do: 0x2018
  defp windows_1252_codepoint(0x92), do: 0x2019
  defp windows_1252_codepoint(0x93), do: 0x201C
  defp windows_1252_codepoint(0x94), do: 0x201D
  defp windows_1252_codepoint(0x95), do: 0x2022
  defp windows_1252_codepoint(0x96), do: 0x2013
  defp windows_1252_codepoint(0x97), do: 0x2014
  defp windows_1252_codepoint(0x98), do: 0x02DC
  defp windows_1252_codepoint(0x99), do: 0x2122
  defp windows_1252_codepoint(0x9A), do: 0x0161
  defp windows_1252_codepoint(0x9B), do: 0x203A
  defp windows_1252_codepoint(0x9C), do: 0x0153
  defp windows_1252_codepoint(0x9E), do: 0x017E
  defp windows_1252_codepoint(0x9F), do: 0x0178
  defp windows_1252_codepoint(byte), do: byte

  defp extract_body_text_with_newlines(parsed_html) do
    nodes =
      case Floki.find(parsed_html, "body") do
        [] -> parsed_html
        body -> body
      end

    blocks =
      nodes
      |> extract_text_blocks()
      |> Enum.reject(&(&1 == ""))

    case blocks do
      [] -> Floki.text(nodes, sep: "\n")
      _ -> Enum.join(blocks, "\n\n")
    end
  end

  defp extract_text_blocks(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &extract_text_blocks/1)
  end

  defp extract_text_blocks(text) when is_binary(text) do
    case normalize_inline_whitespace(text) do
      "" -> []
      cleaned -> [cleaned]
    end
  end

  defp extract_text_blocks({tag, _attrs, children} = node) do
    cond do
      skip_text_tag?(tag) ->
        []

      block_tag?(tag) and has_direct_block_children?(children) ->
        extract_text_blocks(children)

      block_tag?(tag) ->
        case node |> Floki.text(sep: " ") |> normalize_inline_whitespace() do
          "" -> []
          cleaned -> [cleaned]
        end

      true ->
        extract_text_blocks(children)
    end
  end

  defp extract_text_blocks(_), do: []

  defp block_tag?(tag) do
    tag in [
      "address",
      "article",
      "aside",
      "blockquote",
      "dd",
      "div",
      "dl",
      "dt",
      "figcaption",
      "figure",
      "footer",
      "form",
      "h1",
      "h2",
      "h3",
      "h4",
      "h5",
      "h6",
      "header",
      "li",
      "main",
      "nav",
      "ol",
      "p",
      "pre",
      "section",
      "table",
      "tbody",
      "td",
      "tfoot",
      "th",
      "thead",
      "tr",
      "ul"
    ]
  end

  defp has_direct_block_children?(children) when is_list(children) do
    Enum.any?(children, fn
      {child_tag, _, _} -> block_tag?(child_tag)
      _ -> false
    end)
  end

  defp has_direct_block_children?(_), do: false

  defp skip_text_tag?(tag), do: tag in ["head", "script", "style", "noscript", "title"]

  defp normalize_inline_whitespace(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp decode_html_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace(~r/&#(\d+);/, fn match ->
      # Extract the number from &#123; format
      num_str = String.slice(match, 2..-2)
      num = String.to_integer(num_str)
      <<num::utf8>>
    end)
    |> String.replace(~r/&#x([0-9a-fA-F]+);/, fn match ->
      # Extract the hex from &#xABC; format
      hex_str = String.slice(match, 3..-2)
      num = String.to_integer(hex_str, 16)
      <<num::utf8>>
    end)
  end

  defp normalize_newlines(text) do
    text
    # Collapse 3+ newlines to double newline
    |> String.replace(~r/\n{3,}/, "\n\n")
    # Ensure we have paragraph breaks, not excessive whitespace
    |> String.replace(~r/[ \t]*\n[ \t]*/, "\n")
  end

  defp cleanup_noise_lines(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&noise_line?/1)
    |> join_drop_cap_lines()
    |> Enum.join("\n")
  end

  defp noise_line?(""), do: false

  defp noise_line?(line) do
    String.match?(line, ~r/^\d{10,13}(-\d+)?$/) or
      String.starts_with?(line, "@page") or
      String.match?(line, ~r/^[.#]?[a-zA-Z0-9_-]+\s*\{.*\}\s*$/)
  end

  defp join_drop_cap_lines(lines), do: do_join_drop_cap_lines(lines, [])

  defp do_join_drop_cap_lines([], acc), do: Enum.reverse(acc)

  defp do_join_drop_cap_lines([single, next | rest], acc)
       when byte_size(single) == 1 do
    if String.match?(next, ~r/^\p{Ll}/u) do
      do_join_drop_cap_lines([single <> next | rest], acc)
    else
      do_join_drop_cap_lines([next | rest], [single | acc])
    end
  end

  defp do_join_drop_cap_lines([line | rest], acc), do: do_join_drop_cap_lines(rest, [line | acc])

  defp maybe_repair_mojibake(text) do
    if String.contains?(text, ["Ã", "Â", "â"]) do
      repaired =
        try do
          :unicode.characters_to_binary(text, :utf8, :latin1)
        rescue
          _ -> nil
        end

      cond do
        !is_binary(repaired) ->
          text

        !String.valid?(repaired) ->
          text

        mojibake_score(repaired) < mojibake_score(text) ->
          repaired

        true ->
          text
      end
    else
      text
    end
  end

  defp mojibake_score(text) do
    Enum.reduce(@mojibake_markers, 0, fn marker, acc ->
      acc + (String.split(text, marker) |> length()) - 1
    end)
  end
end
