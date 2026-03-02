defmodule Lex.Library.CalibreScanner do
  @moduledoc """
  Scans the Calibre library folder for EPUB files and checks their import status.

  Provides functionality to:
  - Recursively find all EPUB files in the configured Calibre folder
  - Parse metadata from each EPUB
  - Check if books have already been imported into the database
  - Return structured data with file path, metadata, and import status
  """

  alias Lex.Library
  alias Lex.Library.{Document, EPUB}
  alias Lex.Repo

  import Ecto.Query

  require Logger

  defstruct [
    :file_path,
    :title,
    :author,
    :language,
    :import_status,
    :document_id
  ]

  @type t :: %__MODULE__{
          file_path: String.t(),
          title: String.t(),
          author: String.t(),
          language: String.t(),
          import_status: :not_imported | :imported | :error,
          document_id: integer() | nil
        }

  @doc """
  Scans the Calibre library folder and returns a list of CalibreBook structs.

  For each EPUB file found:
  1. Parses the metadata (title, author, language)
  2. Checks if it's already imported (matches on source_file)
  3. Returns structured data with import status

  Files that fail to parse are logged as warnings and included in the result
  with an `:error` import status.

  ## Returns
    - `{:ok, [%CalibreScanner{}]}` - List of books with metadata and import status
    - `{:error, :calibre_path_not_configured}` - Calibre path not configured
    - `{:error, :calibre_path_not_found}` - Calibre path doesn't exist
  """
  @spec scan() :: {:ok, [t()]} | {:error, atom()}
  def scan do
    calibre_path = Library.calibre_library_path()

    cond do
      is_nil(calibre_path) or calibre_path == "" ->
        {:error, :calibre_path_not_configured}

      not File.exists?(calibre_path) ->
        {:error, :calibre_path_not_found}

      true ->
        do_scan(calibre_path)
    end
  end

  defp do_scan(calibre_path) do
    # Find all EPUB files recursively
    epub_files =
      calibre_path
      |> Path.join("**/*.epub")
      |> Path.wildcard()

    if Enum.empty?(epub_files) do
      {:ok, []}
    else
      # Batch query to check which files are already imported
      imported_docs = get_imported_documents(epub_files)

      # Process each file and build the result
      books =
        Enum.map(epub_files, fn file_path ->
          process_epub_file(file_path, imported_docs)
        end)

      {:ok, books}
    end
  end

  defp get_imported_documents(file_paths) do
    # Query all documents that match the given source_file paths
    # Returns a map of source_file => document_id for quick lookup
    file_paths
    |> Enum.map(&normalize_path/1)
    |> then(fn normalized_paths ->
      Document
      |> where([d], d.source_file in ^normalized_paths)
      |> select([d], {d.source_file, d.id})
      |> Repo.all()
      |> Map.new()
    end)
  end

  defp normalize_path(path) do
    # Normalize the path for consistent comparison
    Path.expand(path)
  end

  defp process_epub_file(file_path, imported_docs) do
    normalized_path = normalize_path(file_path)

    # Check if this file is already imported
    case Map.get(imported_docs, normalized_path) do
      nil ->
        # Not imported, parse metadata
        parse_and_create_book(file_path)

      document_id ->
        # Already imported, fetch document details
        create_imported_book(file_path, document_id)
    end
  end

  defp parse_and_create_book(file_path) do
    case EPUB.parse_metadata(file_path) do
      {:ok, metadata} ->
        %__MODULE__{
          file_path: file_path,
          title: metadata.title,
          author: metadata.author,
          language: metadata.language,
          import_status: :not_imported,
          document_id: nil
        }

      {:error, reason} ->
        Logger.warning("Failed to parse EPUB metadata for #{file_path}: #{inspect(reason)}")

        %__MODULE__{
          file_path: file_path,
          title: Path.basename(file_path, ".epub"),
          author: "Unknown",
          language: "es",
          import_status: :error,
          document_id: nil
        }
    end
  end

  defp create_imported_book(file_path, document_id) do
    # Fetch document details from database
    case Repo.get(Document, document_id) do
      nil ->
        # Document was deleted, treat as not imported
        Logger.warning(
          "Document #{document_id} not found for imported file #{file_path}, treating as not imported"
        )

        parse_and_create_book(file_path)

      document ->
        %__MODULE__{
          file_path: file_path,
          title: document.title,
          author: document.author || "Unknown",
          language: document.language,
          import_status: :imported,
          document_id: document_id
        }
    end
  end
end
