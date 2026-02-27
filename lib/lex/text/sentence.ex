defmodule Lex.Text.Sentence do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sentences" do
    field(:position, :integer)
    field(:text, :string)
    field(:char_start, :integer)
    field(:char_end, :integer)

    belongs_to(:section, Lex.Library.Section)

    timestamps()
  end

  @doc false
  def changeset(sentence, attrs) do
    sentence
    |> cast(attrs, [:position, :text, :char_start, :char_end, :section_id])
    |> validate_required([:position, :text, :section_id])
    |> validate_number(:position, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:section_id)
    |> unique_constraint([:section_id, :position])
  end
end
