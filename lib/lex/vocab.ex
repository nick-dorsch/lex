defmodule Lex.Vocab do
  @moduledoc """
  The Vocab context - User lexeme states and LLM help requests.
  """

  alias Lex.Repo
  alias Lex.Vocab.UserLexemeState
  alias Lex.Vocab.LlmHelpRequest
  alias Lex.Text.Token

  import Ecto.Query

  @doc """
  Marks all non-punctuation lexemes in a sentence as seen for a user.

  When a sentence is first displayed:
  1. Gets all non-punctuation tokens in the sentence
  2. For each token's lexeme, checks if user_lexeme_state exists
  3. For lexemes with no state, creates user_lexeme_state with status="seen"
  4. For existing "seen" entries, increments seen_count and updates last_seen_at
  5. For "learning" or "known" entries, does nothing (preserves higher states)

  ## Examples

      iex> mark_lexemes_seen(user_id, sentence_id)
      {:ok, [%UserLexemeState{}]}

      iex> mark_lexemes_seen(invalid_user_id, sentence_id)
      {:error, %Ecto.Changeset{}}
  """
  @spec mark_lexemes_seen(integer(), integer()) ::
          {:ok, [UserLexemeState.t()]} | {:error, Ecto.Changeset.t()}
  def mark_lexemes_seen(user_id, sentence_id) do
    # Get all non-punctuation tokens for the sentence with their lexeme IDs
    lexeme_ids =
      Token
      |> where([t], t.sentence_id == ^sentence_id and t.is_punctuation == false)
      |> select([t], t.lexeme_id)
      |> distinct(true)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)

    # Process each lexeme within a transaction
    Repo.transaction(fn ->
      Enum.map(lexeme_ids, fn lexeme_id ->
        mark_single_lexeme_seen(user_id, lexeme_id)
      end)
    end)
  end

  # Marks a single lexeme as seen, respecting existing states
  defp mark_single_lexeme_seen(user_id, lexeme_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Try to find existing state
    existing_state =
      UserLexemeState
      |> where(user_id: ^user_id, lexeme_id: ^lexeme_id)
      |> Repo.one()

    case existing_state do
      nil ->
        # No state exists, create new "seen" state
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user_id,
          lexeme_id: lexeme_id,
          status: "seen",
          seen_count: 1,
          first_seen_at: now,
          last_seen_at: now
        })
        |> Repo.insert!()

      %{status: "seen"} = state ->
        # Already seen, increment count and update timestamp
        state
        |> UserLexemeState.mark_as_seen()
        |> Repo.update!()

      state when state.status in ["learning", "known"] ->
        # Preserve higher states, do nothing
        state
    end
  end

  @doc """
  Toggles the learning state for a lexeme.

  When user triggers "toggle learning":
  1. Gets lexeme for focused token
  2. Checks current state:
     - If no state or `seen`: create/update to `learning`, set `learning_since`
     - If `learning`: revert to `seen` (not `known`)
     - If `known`: revert to `learning` for relearning

  ## Examples

      iex> toggle_learning(user_id, lexeme_id)
      {:ok, %UserLexemeState{status: "learning"}}

      iex> toggle_learning(user_id, lexeme_id_already_learning)
      {:ok, %UserLexemeState{status: "seen"}}

      iex> toggle_learning(user_id, lexeme_id_known)
      {:ok, %UserLexemeState{status: "learning"}}
  """
  @spec toggle_learning(integer(), integer()) ::
          {:ok, UserLexemeState.t()} | {:error, Ecto.Changeset.t()}
  def toggle_learning(user_id, lexeme_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Try to find existing state
    existing_state =
      UserLexemeState
      |> where(user_id: ^user_id, lexeme_id: ^lexeme_id)
      |> Repo.one()

    case existing_state do
      nil ->
        # No state exists, create new "learning" state
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user_id,
          lexeme_id: lexeme_id,
          status: "learning",
          seen_count: 1,
          first_seen_at: now,
          last_seen_at: now,
          learning_since: now
        })
        |> Repo.insert()

      %{status: "known"} = state ->
        # Allow relearning known words
        attrs = %{
          status: "learning",
          learning_since: now,
          known_at: nil,
          seen_count: state.seen_count + 1,
          last_seen_at: now
        }

        state
        |> UserLexemeState.changeset(attrs)
        |> Repo.update()

      %{status: "learning"} = state ->
        # Revert from learning to seen
        attrs = %{
          status: "seen",
          learning_since: nil,
          known_at: nil,
          seen_count: state.seen_count + 1,
          last_seen_at: now
        }

        state
        |> UserLexemeState.changeset(attrs)
        |> Repo.update()

      state when state.status in ["seen", nil] ->
        # Promote to learning
        attrs = %{
          status: "learning",
          learning_since: now,
          seen_count: state.seen_count + 1,
          last_seen_at: now
        }

        attrs =
          if is_nil(state.first_seen_at) do
            Map.put(attrs, :first_seen_at, now)
          else
            attrs
          end

        state
        |> UserLexemeState.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Marks a lexeme as learning (directly, not a toggle).

  When user requests LLM help for a token:
  1. Gets the lexeme for the token
  2. Sets status to "learning" regardless of current state
  3. Updates learning_since timestamp

  Unlike toggle_learning/2, this always sets to learning and never toggles back.

  ## Examples

      iex> mark_learning(user_id, lexeme_id)
      {:ok, %UserLexemeState{status: "learning"}}

      iex> mark_learning(user_id, lexeme_id_already_learning)
      {:ok, %UserLexemeState{status: "learning"}}  # unchanged
  """
  @spec mark_learning(integer(), integer()) ::
          {:ok, UserLexemeState.t()} | {:error, Ecto.Changeset.t()}
  def mark_learning(user_id, lexeme_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Try to find existing state
    existing_state =
      UserLexemeState
      |> where(user_id: ^user_id, lexeme_id: ^lexeme_id)
      |> Repo.one()

    case existing_state do
      nil ->
        # No state exists, create new "learning" state
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user_id,
          lexeme_id: lexeme_id,
          status: "learning",
          seen_count: 1,
          first_seen_at: now,
          last_seen_at: now,
          learning_since: now
        })
        |> Repo.insert()

      %UserLexemeState{status: "learning"} = state ->
        # Already learning, no change needed
        {:ok, state}

      state ->
        # Update to learning
        attrs = %{
          status: "learning",
          learning_since: now,
          seen_count: state.seen_count + 1,
          last_seen_at: now
        }

        attrs =
          if is_nil(state.first_seen_at) do
            Map.put(attrs, :first_seen_at, now)
          else
            attrs
          end

        state
        |> UserLexemeState.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Advances a lexeme state for token-level help requests.

  State progression:
  - `nil` / `seen` -> `learning`
  - `learning` -> `known`
  - `known` -> `learning` (for relearning)
  """
  @spec advance_help_state(integer(), integer()) ::
          {:ok, UserLexemeState.t()} | {:error, Ecto.Changeset.t()}
  def advance_help_state(user_id, lexeme_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    existing_state =
      UserLexemeState
      |> where(user_id: ^user_id, lexeme_id: ^lexeme_id)
      |> Repo.one()

    case existing_state do
      nil ->
        %UserLexemeState{}
        |> UserLexemeState.changeset(%{
          user_id: user_id,
          lexeme_id: lexeme_id,
          status: "learning",
          seen_count: 1,
          first_seen_at: now,
          last_seen_at: now,
          learning_since: now
        })
        |> Repo.insert()

      %UserLexemeState{status: "learning"} = state ->
        state
        |> UserLexemeState.mark_as_known()
        |> Repo.update()

      %UserLexemeState{status: "known"} = state ->
        attrs = %{
          status: "learning",
          learning_since: now,
          known_at: nil,
          seen_count: state.seen_count + 1,
          last_seen_at: now
        }

        state
        |> UserLexemeState.changeset(attrs)
        |> Repo.update()

      state ->
        state
        |> UserLexemeState.mark_as_learning()
        |> Repo.update()
    end
  end

  @doc """
  Returns total lexeme counts by status for a user.

  Counts are global across all documents.
  """
  @spec get_status_counts(integer()) :: %{
          known: non_neg_integer(),
          learning: non_neg_integer(),
          read: non_neg_integer()
        }
  def get_status_counts(user_id) do
    known_count = count_states_by_status(user_id, "known")
    learning_count = count_states_by_status(user_id, "learning")
    read_count = count_all_states(user_id)

    %{
      known: known_count,
      learning: learning_count,
      read: read_count
    }
  end

  defp count_states_by_status(user_id, status) do
    UserLexemeState
    |> where([s], s.user_id == ^user_id and s.status == ^status)
    |> Repo.aggregate(:count, :id)
  end

  defp count_all_states(user_id) do
    UserLexemeState
    |> where([s], s.user_id == ^user_id and s.status in ["seen", "learning", "known"])
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Logs an LLM help request.

  Creates a record in the llm_help_requests table with provider and model
  from configuration. This is called when the user requests LLM help.

  ## Examples

      iex> log_llm_request(user_id, document_id, sentence_id, token_id, :token)
      {:ok, %LlmHelpRequest{}}

      iex> log_llm_request(user_id, document_id, sentence_id, nil, :sentence)
      {:ok, %LlmHelpRequest{}}
  """
  @spec log_llm_request(integer(), integer(), integer(), integer() | nil, :token | :sentence) ::
          {:ok, LlmHelpRequest.t()} | {:error, Ecto.Changeset.t()}
  def log_llm_request(user_id, document_id, sentence_id, token_id, request_type) do
    # Verify document exists
    document = Repo.get(Lex.Library.Document, document_id)

    if is_nil(document) do
      {:error,
       %LlmHelpRequest{}
       |> LlmHelpRequest.changeset(%{document_id: document_id})
       |> Ecto.Changeset.add_error(:document_id, "does not exist")}
    else
      # Get provider and model from config, with defaults
      provider = Application.get_env(:lex, :llm_provider, "openai")
      model = Application.get_env(:lex, :llm_model, "gpt-4")

      attrs = %{
        user_id: user_id,
        document_id: document_id,
        sentence_id: sentence_id,
        token_id: token_id,
        request_type: Atom.to_string(request_type),
        response_language: document.language,
        provider: provider,
        model: model
      }

      %LlmHelpRequest{}
      |> LlmHelpRequest.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Promotes all 'seen' lexemes in a sentence to 'known' status.

  When user advances to the next sentence (j key pressed):
  1. Gets all non-punctuation tokens in the sentence being left
  2. For each token's lexeme with status="seen", updates to status="known"
  3. Sets known_at timestamp for promoted lexemes
  4. Lexemes with status="learning" or "known" remain unchanged

  ## Examples

      iex> promote_seen_to_known(user_id, sentence_id)
      {:ok, 3}  # 3 lexemes were promoted

      iex> promote_seen_to_known(invalid_user_id, sentence_id)
      {:error, reason}
  """
  @spec promote_seen_to_known(integer(), integer()) ::
          {:ok, non_neg_integer()} | {:error, any()}
  def promote_seen_to_known(user_id, sentence_id) do
    # Get all non-punctuation lexeme IDs for the sentence
    lexeme_ids =
      Token
      |> where([t], t.sentence_id == ^sentence_id and t.is_punctuation == false)
      |> select([t], t.lexeme_id)
      |> distinct(true)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)

    if lexeme_ids == [] do
      {:ok, 0}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Update all 'seen' states to 'known' in a single query
      {count, _} =
        UserLexemeState
        |> where([s], s.user_id == ^user_id and s.lexeme_id in ^lexeme_ids and s.status == "seen")
        |> Repo.update_all(
          set: [
            status: "known",
            known_at: now,
            last_seen_at: now,
            updated_at: now
          ]
        )

      {:ok, count}
    end
  end
end
