defmodule Lex.Vocab do
  @moduledoc """
  The Vocab context - User lexeme states.
  """

  alias Lex.Repo
  alias Lex.Vocab.UserLexemeState
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
end
