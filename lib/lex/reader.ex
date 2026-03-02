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
  Gets the next sentence in the document.

  Returns the next sentence within the current section if available.
  If at the last sentence of the current section, returns the first sentence
  of the next section. If at the last sentence of the document, returns
  an error indicating the end of the document.

  ## Examples

      iex> next_sentence(document_id, current_section_id, current_sentence_id)
      {:ok, %{section: %Section{}, sentence: %Sentence{}}}

      iex> next_sentence(document_id, last_section_id, last_sentence_id)
      {:error, :end_of_document}
  """
  @spec next_sentence(integer(), integer(), integer()) ::
          {:ok, %{section: Section.t(), sentence: Sentence.t()}} | {:error, :end_of_document}
  def next_sentence(document_id, current_section_id, current_sentence_id) do
    # Get current section to find its position
    current_section = Repo.get(Section, current_section_id)

    # Try to get next sentence in current section
    next_in_section =
      Sentence
      |> where(section_id: ^current_section_id)
      |> where([s], s.id > ^current_sentence_id)
      |> order_by(asc: :position)
      |> limit(1)
      |> Repo.one()

    case next_in_section do
      %Sentence{} = sentence ->
        {:ok, %{section: current_section, sentence: sentence}}

      nil ->
        # No more sentences in current section, try next sections
        find_next_sentence_in_sections(document_id, current_section.position)
    end
  end

  # Recursively find the next sentence starting from sections after the given position
  defp find_next_sentence_in_sections(document_id, after_position) do
    # Get the next section
    next_section =
      Section
      |> where(document_id: ^document_id)
      |> where([s], s.position > ^after_position)
      |> order_by(asc: :position)
      |> limit(1)
      |> Repo.one()

    case next_section do
      nil ->
        {:error, :end_of_document}

      %Section{} = section ->
        # Get first sentence of this section
        first_sentence =
          Sentence
          |> where(section_id: ^section.id)
          |> order_by(asc: :position)
          |> limit(1)
          |> Repo.one()

        case first_sentence do
          nil ->
            # Section has no sentences, try the next one
            find_next_sentence_in_sections(document_id, section.position)

          %Sentence{} = sentence ->
            {:ok, %{section: section, sentence: sentence}}
        end
    end
  end

  @doc """
  Gets the previous sentence in the document.

  Returns the previous sentence within the current section if available.
  If at the first sentence of the current section, returns the last sentence
  of the previous section. If at the first sentence of the document, returns
  an error indicating the start of the document.

  ## Examples

      iex> previous_sentence(document_id, current_section_id, current_sentence_id)
      {:ok, %{section: %Section{}, sentence: %Sentence{}}}

      iex> previous_sentence(document_id, first_section_id, first_sentence_id)
      {:error, :start_of_document}
  """
  @spec previous_sentence(integer(), integer(), integer()) ::
          {:ok, %{section: Section.t(), sentence: Sentence.t()}} | {:error, :start_of_document}
  def previous_sentence(document_id, current_section_id, current_sentence_id) do
    # Get current section to find its position
    current_section = Repo.get(Section, current_section_id)

    # Try to get previous sentence in current section
    prev_in_section =
      Sentence
      |> where(section_id: ^current_section_id)
      |> where([s], s.id < ^current_sentence_id)
      |> order_by(desc: :position)
      |> limit(1)
      |> Repo.one()

    case prev_in_section do
      %Sentence{} = sentence ->
        {:ok, %{section: current_section, sentence: sentence}}

      nil ->
        # No previous sentences in current section, try previous sections
        find_previous_sentence_in_sections(document_id, current_section.position)
    end
  end

  # Recursively find the previous sentence starting from sections before the given position
  defp find_previous_sentence_in_sections(document_id, before_position) do
    # Get the previous section
    prev_section =
      Section
      |> where(document_id: ^document_id)
      |> where([s], s.position < ^before_position)
      |> order_by(desc: :position)
      |> limit(1)
      |> Repo.one()

    case prev_section do
      nil ->
        {:error, :start_of_document}

      %Section{} = section ->
        # Get last sentence of this section
        last_sentence =
          Sentence
          |> where(section_id: ^section.id)
          |> order_by(desc: :position)
          |> limit(1)
          |> Repo.one()

        case last_sentence do
          nil ->
            # Section has no sentences, try the previous one
            find_previous_sentence_in_sections(document_id, section.position)

          %Sentence{} = sentence ->
            {:ok, %{section: section, sentence: sentence}}
        end
    end
  end

  @doc """
  Skips to the first sentence of the next section.

  Returns the first sentence of the next section in the document.
  If at the last section, returns an error indicating the end of document.
  Skips empty sections automatically.

  ## Examples

      iex> skip_to_next_section(document_id, current_section_id, current_sentence_id)
      {:ok, %{section: %Section{}, sentence: %Sentence{}, skipped_sentences: 5}}

      iex> skip_to_next_section(document_id, last_section_id, last_sentence_id)
      {:error, :end_of_document}
  """
  @spec skip_to_next_section(integer(), integer(), integer()) ::
          {:ok, %{section: Section.t(), sentence: Sentence.t(), skipped_sentences: integer()}}
          | {:error, :end_of_document}
  def skip_to_next_section(document_id, current_section_id, current_sentence_id) do
    # Get current section and sentence to find positions
    current_section = Repo.get(Section, current_section_id)
    current_sentence = Repo.get(Sentence, current_sentence_id)

    # Count remaining sentences in current section (after current position)
    current_section_remaining =
      Sentence
      |> where(section_id: ^current_section_id)
      |> where([s], s.position > ^current_sentence.position)
      |> Repo.aggregate(:count, :id)

    # Find the next section and accumulate skipped sentences
    skip_to_next_section_recursive(
      document_id,
      current_section.position,
      current_section_remaining
    )
  end

  # Recursive helper that finds the landing section and counts skipped sentences.
  # Skipped sentences include all sentences in sections that are "jumped over"
  # to reach the landing section.
  defp skip_to_next_section_recursive(document_id, after_position, skipped_count) do
    # Get the next section
    next_section =
      Section
      |> where(document_id: ^document_id)
      |> where([s], s.position > ^after_position)
      |> order_by(asc: :position)
      |> limit(1)
      |> Repo.one()

    case next_section do
      nil ->
        {:error, :end_of_document}

      %Section{} = candidate_section ->
        # Count sentences in this candidate section
        section_sentence_count =
          Sentence
          |> where(section_id: ^candidate_section.id)
          |> Repo.aggregate(:count, :id)

        if section_sentence_count == 0 do
          # Empty section, skip it (doesn't add to count since it has no sentences)
          skip_to_next_section_recursive(
            document_id,
            candidate_section.position,
            skipped_count
          )
        else
          # This section has sentences - land here (it's the next section)
          first_sentence =
            Sentence
            |> where(section_id: ^candidate_section.id)
            |> order_by(asc: :position)
            |> limit(1)
            |> Repo.one()

          {:ok,
           %{
             section: candidate_section,
             sentence: first_sentence,
             skipped_sentences: skipped_count
           }}
        end
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
