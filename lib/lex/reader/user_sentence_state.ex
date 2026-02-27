defmodule Lex.Reader.UserSentenceState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_sentence_states" do
    field(:status, :string)
    field(:read_at, :utc_datetime)

    belongs_to(:user, Lex.Accounts.User)
    belongs_to(:sentence, Lex.Text.Sentence)

    timestamps()
  end

  @valid_statuses ["unread", "read"]

  @doc false
  def changeset(user_sentence_state, attrs) do
    user_sentence_state
    |> cast(attrs, [:user_id, :sentence_id, :status, :read_at])
    |> validate_required([:user_id, :sentence_id, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:sentence_id)
    |> unique_constraint([:user_id, :sentence_id])
  end

  @doc """
  Mark the sentence as read.
  """
  def mark_as_read(%__MODULE__{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset(state, %{
      status: "read",
      read_at: now
    })
  end

  @doc """
  Mark the sentence as unread.
  """
  def mark_as_unread(%__MODULE__{} = state) do
    changeset(state, %{
      status: "unread",
      read_at: nil
    })
  end
end
