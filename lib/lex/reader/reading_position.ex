defmodule Lex.Reader.ReadingPosition do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reading_positions" do
    field(:active_token_position, :integer)

    belongs_to(:user, Lex.Accounts.User)
    belongs_to(:document, Lex.Library.Document)
    belongs_to(:section, Lex.Library.Section)
    belongs_to(:sentence, Lex.Text.Sentence)

    timestamps()
  end

  @doc false
  def changeset(reading_position, attrs) do
    reading_position
    |> cast(attrs, [
      :user_id,
      :document_id,
      :section_id,
      :sentence_id,
      :active_token_position
    ])
    |> validate_required([:user_id, :document_id])
    |> validate_number(:active_token_position, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:section_id)
    |> foreign_key_constraint(:sentence_id)
    |> unique_constraint([:user_id, :document_id])
  end
end
