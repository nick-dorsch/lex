defmodule Lex.Text.Token do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tokens" do
    field(:position, :integer)
    field(:surface, :string)
    field(:normalized_surface, :string)
    field(:lemma, :string)
    field(:pos, :string)
    field(:is_punctuation, :boolean, default: false)
    field(:char_start, :integer)
    field(:char_end, :integer)

    belongs_to(:sentence, Lex.Text.Sentence)
    belongs_to(:lexeme, Lex.Text.Lexeme)

    timestamps()
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :sentence_id,
      :position,
      :surface,
      :normalized_surface,
      :lemma,
      :pos,
      :is_punctuation,
      :char_start,
      :char_end,
      :lexeme_id
    ])
    |> validate_required([
      :sentence_id,
      :position,
      :surface,
      :normalized_surface,
      :lemma,
      :pos,
      :is_punctuation
    ])
    |> validate_number(:position, greater_than_or_equal_to: 1)
    |> validate_boolean(:is_punctuation)
    |> foreign_key_constraint(:sentence_id)
    |> foreign_key_constraint(:lexeme_id)
    |> unique_constraint([:sentence_id, :position])
  end

  defp validate_boolean(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      true -> changeset
      false -> changeset
      _ -> add_error(changeset, field, "must be a boolean")
    end
  end
end
