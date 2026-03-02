defmodule Lex.Library.ImportWorker do
  @moduledoc """
  Task worker for async EPUB import operations.

  This module handles the actual import work in a supervised task,
  updating the ImportTracker and broadcasting events on completion or failure.
  """

  alias Lex.Library
  alias Lex.Library.ImportTracker
  require Logger

  @doc """
  Runs the import workflow for a given EPUB file.

  This function is designed to be run within a supervised Task.
  It:
  1. Calls Library.import_epub/2 to perform the actual import
  2. On success: marks complete in tracker and broadcasts event
  3. On failure: marks failed in tracker and broadcasts event with error

  Note: The import must already be marked as started via ImportTracker.start_import/2
  before calling this function.

  ## Parameters
    - file_path: Path to the EPUB file
    - user_id: ID of the user importing the file
    - opts: Options to pass to Library.import_epub/2
  """
  @spec run(String.t(), integer(), keyword()) :: :ok
  def run(file_path, user_id, opts) do
    Logger.info("Running async import for #{file_path} (user: #{user_id})")
    do_import(file_path, user_id, opts)
  end

  defp do_import(file_path, user_id, opts) do
    case Library.import_epub(file_path, [{:user_id, user_id} | opts]) do
      {:ok, document} ->
        Logger.info("Successfully imported #{file_path} as document #{document.id}")
        ImportTracker.complete_import(file_path, document.id, user_id)
        :ok

      {:error, reason} ->
        error_message = format_error(reason)
        Logger.error("Failed to import #{file_path}: #{error_message}")
        ImportTracker.fail_import(file_path, error_message, user_id)
        :ok
    end
  end

  defp format_error({:epub_parse_failed, reason}) do
    "EPUB parsing failed: #{inspect(reason)}"
  end

  defp format_error({:nlp_failed, section, reason}) do
    "NLP processing failed for section '#{section}': #{inspect(reason)}"
  end

  defp format_error({:validation_failed, %Ecto.Changeset{} = changeset}) do
    "Validation failed: #{format_changeset_errors(changeset)}"
  end

  defp format_error({:validation_failed, reason}) do
    "Validation failed: #{inspect(reason)}"
  end

  defp format_error(reason) do
    inspect(reason)
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
