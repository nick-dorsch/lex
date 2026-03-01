defmodule Lex.Vocab.UserLexemeState do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          status: String.t(),
          seen_count: integer(),
          first_seen_at: DateTime.t() | nil,
          last_seen_at: DateTime.t() | nil,
          known_at: DateTime.t() | nil,
          learning_since: DateTime.t() | nil,
          user_id: integer(),
          lexeme_id: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "user_lexeme_states" do
    field(:status, :string)
    field(:seen_count, :integer, default: 0)
    field(:first_seen_at, :utc_datetime)
    field(:last_seen_at, :utc_datetime)
    field(:known_at, :utc_datetime)
    field(:learning_since, :utc_datetime)

    belongs_to(:user, Lex.Accounts.User)
    belongs_to(:lexeme, Lex.Text.Lexeme)

    timestamps()
  end

  @valid_statuses ["seen", "learning", "known"]

  @doc false
  def changeset(user_lexeme_state, attrs) do
    user_lexeme_state
    |> cast(attrs, [
      :user_id,
      :lexeme_id,
      :status,
      :seen_count,
      :first_seen_at,
      :last_seen_at,
      :known_at,
      :learning_since
    ])
    |> validate_required([:user_id, :lexeme_id, :status, :seen_count])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:seen_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:lexeme_id)
    |> unique_constraint([:user_id, :lexeme_id])
  end

  @doc """
  Mark the lexeme state as seen.
  """
  def mark_as_seen(%__MODULE__{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      status: "seen",
      seen_count: state.seen_count + 1,
      last_seen_at: now
    }

    attrs =
      if is_nil(state.first_seen_at) do
        Map.put(attrs, :first_seen_at, now)
      else
        attrs
      end

    changeset(state, attrs)
  end

  @doc """
  Mark the lexeme state as learning.
  """
  def mark_as_learning(%__MODULE__{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

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

    changeset(state, attrs)
  end

  @doc """
  Mark the lexeme state as known.
  """
  def mark_as_known(%__MODULE__{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      status: "known",
      known_at: now,
      seen_count: state.seen_count + 1,
      last_seen_at: now
    }

    attrs =
      if is_nil(state.first_seen_at) do
        Map.put(attrs, :first_seen_at, now)
      else
        attrs
      end

    changeset(state, attrs)
  end
end
