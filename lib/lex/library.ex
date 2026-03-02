defmodule Lex.Library do
  @moduledoc """
  The Library context - Documents, sections, ingestion.
  """

  import Ecto.Query

  alias Lex.Library.{Document, EPUB, ImportTracker, ImportWorker, Section}
  alias Lex.Repo
  alias Lex.Text.{Lexeme, NLP, Sentence, Token}
  require Logger

  @doc """
  Returns the configured Calibre library path.

  The path is read from the `CALIBRE_LIBRARY_PATH` environment variable,
  defaulting to `~/CalibreLibrary`. The path is expanded to an absolute path.

  Returns the expanded path as a string. Logs a warning if the path doesn't exist.
  """
  @spec calibre_library_path() :: String.t()
  def calibre_library_path() do
    path =
      Application.fetch_env!(:lex, :calibre_library_path)
      |> Path.expand()

    unless File.exists?(path) do
      Logger.warning("Calibre library path does not exist: #{path}")
    end

    path
  end

  @doc """
  Imports an EPUB file and creates all associated database records.

  ## Options
    - `:user_id` (required) - User to associate document with
    - `:source_file` - Override source path in Document (default: file_path)

  ## Returns
    - `{:ok, %Document{}}` - Successfully imported document
    - `{:error, {:epub_parse_failed, reason}}` - EPUB parsing error
    - `{:error, {:nlp_failed, section_title, reason}}` - NLP processing error
    - `{:error, {:validation_failed, changeset}}` - Database validation error
  """
  @spec import_epub(Path.t(), keyword()) ::
          {:ok, Document.t()}
          | {:error,
             {:epub_parse_failed, any()}
             | {:nlp_failed, String.t(), any()}
             | {:validation_failed, Ecto.Changeset.t()}}
  def import_epub(file_path, opts \\ []) do
    user_id = Keyword.fetch!(opts, :user_id)
    source_file = Keyword.get(opts, :source_file, file_path)

    Repo.transaction(fn ->
      with {:ok, document} <- create_document(file_path, source_file, user_id),
           {:ok, _sections} <- process_chapters(document, file_path) do
        finalize_document(document)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, document} -> {:ok, document}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_document(file_path, source_file, user_id) do
    case EPUB.parse_metadata(file_path) do
      {:ok, metadata} ->
        %Document{}
        |> Document.changeset(%{
          title: metadata.title,
          author: metadata.author,
          language: metadata.language,
          status: "uploaded",
          source_file: source_file,
          user_id: user_id
        })
        |> Repo.insert()
        |> case do
          {:ok, document} -> {:ok, document}
          {:error, changeset} -> {:error, {:validation_failed, changeset}}
        end

      {:error, reason} ->
        {:error, {:epub_parse_failed, reason}}
    end
  end

  defp process_chapters(document, file_path) do
    case EPUB.list_chapters(file_path) do
      {:ok, chapters} ->
        results =
          Enum.map(chapters, fn chapter ->
            process_chapter(document, file_path, chapter)
          end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:ok, Enum.map(results, fn {:ok, section} -> section end)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:epub_parse_failed, reason}}
    end
  end

  defp process_chapter(document, file_path, chapter) do
    # Create section
    section_attrs = %{
      document_id: document.id,
      position: chapter.position,
      title: chapter.title,
      source_href: chapter.href
    }

    with {:ok, section} <- create_section(section_attrs),
         {:ok, chapter_text} <- EPUB.get_chapter_content(file_path, chapter.href) do
      process_chapter_text(section, chapter_text, document.language, chapter.title)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, {:validation_failed, changeset}}

      {:error, reason} ->
        {:error, {:epub_parse_failed, reason}}
    end
  end

  defp create_section(attrs) do
    %Section{}
    |> Section.changeset(attrs)
    |> Repo.insert()
  end

  defp process_chapter_text(section, text, language, section_title) do
    case NLP.process_text(text, language: language) do
      {:ok, sentences_data} ->
        results =
          Enum.with_index(sentences_data, 1)
          |> Enum.map(fn {sentence_data, idx} ->
            process_sentence(section, sentence_data, idx, language)
          end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:ok, section}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:nlp_failed, section_title, reason}}
    end
  end

  defp process_sentence(section, sentence_data, position, language) do
    sentence_attrs = %{
      section_id: section.id,
      position: position,
      text: sentence_data["text"],
      char_start: sentence_data["char_start"],
      char_end: sentence_data["char_end"]
    }

    with {:ok, sentence} <- create_sentence(sentence_attrs),
         {:ok, _tokens} <- process_tokens(sentence, sentence_data["tokens"], language) do
      {:ok, sentence}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, {:validation_failed, changeset}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_sentence(attrs) do
    %Sentence{}
    |> Sentence.changeset(attrs)
    |> Repo.insert()
  end

  defp process_tokens(sentence, tokens_data, language) do
    results =
      Enum.with_index(tokens_data, 1)
      |> Enum.map(fn {token_data, idx} ->
        process_token(sentence, token_data, idx, language)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, token} -> token end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_token(sentence, token_data, position, language) do
    normalized_lemma = token_data["normalized_surface"]
    lemma = token_data["lemma"]
    pos = token_data["pos"]

    # Find or create lexeme
    case find_or_create_lexeme(language, normalized_lemma, lemma, pos) do
      {:ok, lexeme} ->
        token_attrs = %{
          sentence_id: sentence.id,
          lexeme_id: lexeme.id,
          position: position,
          surface: token_data["surface"],
          normalized_surface: normalized_lemma,
          lemma: lemma,
          pos: pos,
          is_punctuation: token_data["is_punctuation"],
          char_start: token_data["char_start"],
          char_end: token_data["char_end"]
        }

        %Token{}
        |> Token.changeset(token_attrs)
        |> Repo.insert()
        |> case do
          {:ok, token} -> {:ok, token}
          {:error, changeset} -> {:error, {:validation_failed, changeset}}
        end

      {:error, changeset} ->
        {:error, {:validation_failed, changeset}}
    end
  end

  defp find_or_create_lexeme(language, normalized_lemma, lemma, pos) do
    lexeme_key = [language: language, normalized_lemma: normalized_lemma, pos: pos]

    case Repo.get_by(Lexeme, lexeme_key) do
      nil -> create_lexeme_with_race_handling(lexeme_key, lemma)
      lexeme -> {:ok, lexeme}
    end
  end

  defp create_lexeme_with_race_handling(lexeme_key, lemma) do
    attrs = Keyword.merge(lexeme_key, lemma: lemma)

    %Lexeme{}
    |> Lexeme.changeset(Map.new(attrs))
    |> Repo.insert()
    |> handle_insert_result(lexeme_key)
  end

  defp handle_insert_result({:ok, lexeme}, _key), do: {:ok, lexeme}

  defp handle_insert_result(
         {:error, %Ecto.Changeset{errors: [{:language, {_, [constraint: :unique]}}]}},
         key
       ) do
    # Race condition: another process created it, try fetching again
    case Repo.get_by(Lexeme, key) do
      nil -> {:error, :lexeme_creation_failed}
      lexeme -> {:ok, lexeme}
    end
  end

  defp handle_insert_result({:error, changeset}, _key), do: {:error, changeset}

  defp finalize_document(document) do
    document
    |> Document.changeset(%{status: "ready"})
    |> Repo.update()
    |> case do
      {:ok, document} -> document
      {:error, changeset} -> Repo.rollback({:validation_failed, changeset})
    end
  end

  @doc """
  Asynchronously imports an EPUB file using a supervised Task.

  ## Options
    - `:user_id` (required) - User to associate document with
    - `:source_file` - Override source path in Document (default: file_path)

  ## Returns
    - `{:ok, :started}` - Import was started successfully
    - `{:ok, :already_importing}` - Import is already in progress
    - `{:ok, :already_imported}` - Document already exists for this file
  """
  @spec import_epub_async(Path.t(), integer(), keyword()) ::
          {:ok, :started | :already_importing | :already_imported}
  def import_epub_async(file_path, user_id, opts \\ []) do
    source_file = Keyword.get(opts, :source_file, file_path)

    cond do
      # Check if already importing via ImportTracker
      match?({:importing, _pid}, ImportTracker.get_status(file_path)) ->
        {:ok, :already_importing}

      # Check if already imported in database
      document_exists?(source_file, user_id) ->
        {:ok, :already_imported}

      true ->
        # Start supervised task
        Task.Supervisor.start_child(
          Lex.Library.ImportTaskSupervisor,
          fn ->
            ImportWorker.run(file_path, user_id, opts)
          end,
          restart: :transient
        )

        {:ok, :started}
    end
  end

  defp document_exists?(source_file, user_id) do
    Document
    |> where([d], d.source_file == ^source_file and d.user_id == ^user_id)
    |> Repo.exists?()
  end
end
