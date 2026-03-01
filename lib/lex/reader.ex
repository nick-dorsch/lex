defmodule Lex.Reader do
  @moduledoc """
  The Reader context - Reading positions, navigation.
  """

  alias Lex.Repo
  alias Lex.Reader.ReadingPosition
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence

  import Ecto.Query

  @doc """
  Gets or creates a reading position for a user and document.

  If a position exists, returns it. Otherwise, creates a new position
  at the first sentence of the first section of the document.

  ## Examples

      iex> get_or_create_position(user_id, document_id)
      {:ok, %ReadingPosition{}}

      iex> get_or_create_position(user_id, invalid_document_id)
      {:error, :document_not_found}
  """
  @spec get_or_create_position(integer(), integer()) ::
          {:ok, ReadingPosition.t()} | {:error, :document_not_found | Ecto.Changeset.t()}
  def get_or_create_position(user_id, document_id) do
    # First, try to find an existing position
    position =
      ReadingPosition
      |> where(user_id: ^user_id, document_id: ^document_id)
      |> Repo.one()

    case position do
      nil ->
        # No position exists, create one at the start of the document
        create_position_at_start(user_id, document_id)

      %ReadingPosition{} = existing ->
        {:ok, existing}
    end
  end

  @doc """
  Sets the reading position to a specific section and sentence.

  Updates an existing position record or creates one if it doesn't exist.

  ## Examples

      iex> set_position(user_id, document_id, section_id, sentence_id)
      {:ok, %ReadingPosition{}}

      iex> set_position(user_id, invalid_document_id, section_id, sentence_id)
      {:error, :document_not_found}
  """
  @spec set_position(integer(), integer(), integer(), integer()) ::
          {:ok, ReadingPosition.t()} | {:error, :document_not_found | Ecto.Changeset.t()}
  def set_position(user_id, document_id, section_id, sentence_id) do
    # Verify the document exists
    case Repo.get(Document, document_id) do
      nil ->
        {:error, :document_not_found}

      _document ->
        # Get or create the position, then update it
        ReadingPosition
        |> where(user_id: ^user_id, document_id: ^document_id)
        |> Repo.one()
        |> case do
          nil ->
            %ReadingPosition{}
            |> ReadingPosition.changeset(%{
              user_id: user_id,
              document_id: document_id,
              section_id: section_id,
              sentence_id: sentence_id
            })
            |> Repo.insert()

          %ReadingPosition{} = existing ->
            existing
            |> ReadingPosition.changeset(%{
              section_id: section_id,
              sentence_id: sentence_id
            })
            |> Repo.update()
        end
    end
  end

  # Private helper to create a new position at the start of a document
  defp create_position_at_start(user_id, document_id) do
    # Verify document exists
    case Repo.get(Document, document_id) do
      nil ->
        {:error, :document_not_found}

      _document ->
        create_position_with_section(user_id, document_id)
    end
  end

  defp create_position_with_section(user_id, document_id) do
    first_section =
      Section
      |> where(document_id: ^document_id)
      |> order_by(asc: :position)
      |> limit(1)
      |> Repo.one()

    case first_section do
      nil ->
        # Document has no sections, create position without section/sentence
        %ReadingPosition{}
        |> ReadingPosition.changeset(%{
          user_id: user_id,
          document_id: document_id
        })
        |> Repo.insert()

      section ->
        create_position_with_sentence(user_id, document_id, section)
    end
  end

  defp create_position_with_sentence(user_id, document_id, section) do
    first_sentence =
      Sentence
      |> where(section_id: ^section.id)
      |> order_by(asc: :position)
      |> limit(1)
      |> Repo.one()

    attrs = %{
      user_id: user_id,
      document_id: document_id,
      section_id: section.id
    }

    attrs =
      if first_sentence do
        Map.put(attrs, :sentence_id, first_sentence.id)
      else
        attrs
      end

    %ReadingPosition{}
    |> ReadingPosition.changeset(attrs)
    |> Repo.insert()
  end
end
