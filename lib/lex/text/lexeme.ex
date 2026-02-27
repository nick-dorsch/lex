defmodule Lex.Text.Lexeme do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lexemes" do
    field(:language, :string)
    field(:lemma, :string)
    field(:normalized_lemma, :string)
    field(:pos, :string)

    has_many(:tokens, Lex.Text.Token)

    timestamps()
  end

  @doc false
  def changeset(lexeme, attrs) do
    lexeme
    |> cast(attrs, [:language, :lemma, :normalized_lemma, :pos])
    |> validate_required([:language, :lemma, :normalized_lemma, :pos])
    |> unique_constraint([:language, :normalized_lemma, :pos])
  end
end
