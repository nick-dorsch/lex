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
end
