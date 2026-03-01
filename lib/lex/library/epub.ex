defmodule Lex.Library.EPUB do
  @moduledoc """
  EPUB parsing functionality for extracting metadata and content.
  """

  require Logger

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
              {:ok, List.to_string(content)}

            {:error, _} ->
              # Try with OEBPS/ prefix (common EPUB structure)
              case :zip.zip_get(String.to_charlist("OEBPS/#{href}"), zip_handle) do
                {:ok, {_, content}} when is_binary(content) ->
                  {:ok, content}

                {:ok, {_, content}} when is_list(content) ->
                  {:ok, List.to_string(content)}

                {:error, _} ->
                  # Try with OPS/ prefix (alternative EPUB structure)
                  case :zip.zip_get(String.to_charlist("OPS/#{href}"), zip_handle) do
                    {:ok, {_, content}} when is_binary(content) ->
                      {:ok, content}

                    {:ok, {_, content}} when is_list(content) ->
                      {:ok, List.to_string(content)}

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
    |> Floki.parse_fragment!()
    |> extract_text_with_newlines()
    |> decode_html_entities()
    |> normalize_newlines()
    |> String.trim()
  end

  defp extract_text_with_newlines(parsed_html) do
    parsed_html
    |> Floki.text(sep: "\n")
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
end
