defmodule Lex.Reader do
  @moduledoc """
  The Reader context - Reading positions, navigation.
  """

  alias Lex.Repo
  alias Lex.Reader.ReadingPosition
  alias Lex.Reader.ReadingEvent
  alias Lex.Reader.UserSentenceState
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

  @doc """
  Marks a sentence as read for a user.

  Creates or updates the user_sentence_state record, setting status to "read"
  and recording the current timestamp. This function is idempotent - calling
  it multiple times for the same user/sentence will not create duplicates.

  ## Examples

      iex> mark_sentence_read(user_id, sentence_id)
      {:ok, %UserSentenceState{}}

      iex> mark_sentence_read(invalid_user_id, sentence_id)
      {:error, %Ecto.Changeset{}}
  """
  @spec mark_sentence_read(integer(), integer()) ::
          {:ok, UserSentenceState.t()} | {:error, Ecto.Changeset.t()}
  def mark_sentence_read(user_id, sentence_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Try to find existing state
    case Repo.get_by(UserSentenceState, user_id: user_id, sentence_id: sentence_id) do
      nil ->
        # Create new state
        %UserSentenceState{}
        |> UserSentenceState.changeset(%{
          user_id: user_id,
          sentence_id: sentence_id,
          status: "read",
          read_at: now
        })
        |> Repo.insert()

      %UserSentenceState{} = existing ->
        # Update existing state
        existing
        |> UserSentenceState.changeset(%{
          status: "read",
          read_at: now
        })
        |> Repo.update()
    end
  end

  @doc """
  Logs a reading event for analytics.

  Creates a reading event record with the given user_id, event_type, and metadata.
  Event types are atoms that get converted to strings. The metadata map is
  serialized to JSON for flexible storage.

  ## Event Types

  - :enter_sentence - User views a sentence (on mount/navigate)
  - :advance_sentence - User presses j to advance
  - :skip_range - User skips section
  - :mark_learning - User marks word learning
  - :unmark_learning - User unmarks learning
  - :llm_help_requested - User presses space for help

  ## Examples

      iex> log_event(user_id, :advance_sentence, %{
      ...>   document_id: 1,
      ...>   from_sentence_id: 5,
      ...>   to_sentence_id: 6
      ...> })
      {:ok, %ReadingEvent{}}

      iex> log_event(user_id, :mark_learning, %{
      ...>   document_id: 1,
      ...>   sentence_id: 5,
      ...>   token_id: 12,
      ...>   lexeme_id: 34
      ...> })
      {:ok, %ReadingEvent{}}
  """
  @spec log_event(integer(), atom(), map()) ::
          {:ok, ReadingEvent.t()} | {:error, Ecto.Changeset.t()}
  def log_event(user_id, event_type, metadata \\ %{}) when is_atom(event_type) do
    event_type_str = Atom.to_string(event_type)
    payload = ReadingEvent.encode_payload(metadata)

    attrs = %{
      user_id: user_id,
      event_type: event_type_str,
      payload: payload
    }

    # Extract optional foreign key references from metadata
    attrs =
      case metadata do
        %{document_id: doc_id} -> Map.put(attrs, :document_id, doc_id)
        _ -> attrs
      end

    attrs =
      case metadata do
        %{sentence_id: sent_id} -> Map.put(attrs, :sentence_id, sent_id)
        _ -> attrs
      end

    attrs =
      case metadata do
        %{token_id: tok_id} -> Map.put(attrs, :token_id, tok_id)
        _ -> attrs
      end

    %ReadingEvent{}
    |> ReadingEvent.changeset(attrs)
    |> Repo.insert()
  end
end
