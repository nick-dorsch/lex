defmodule Lex.Library.Section do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sections" do
    field(:position, :integer)
    field(:title, :string)
    field(:source_href, :string)

    belongs_to(:document, Lex.Library.Document)
    has_many(:sentences, Lex.Text.Sentence)

    timestamps()
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:position, :title, :source_href, :document_id])
    |> validate_required([:position, :document_id])
    |> validate_number(:position, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:document_id, :position])
  end
end
