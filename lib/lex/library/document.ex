defmodule Lex.Library.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ["uploaded", "processing", "ready", "failed"]

  schema "documents" do
    field(:title, :string)
    field(:author, :string)
    field(:language, :string)
    field(:status, :string)
    field(:source_file, :string)

    belongs_to(:user, Lex.Accounts.User)
    has_many(:sections, Lex.Library.Section)

    timestamps()
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :author, :language, :status, :source_file, :user_id])
    |> validate_required([:title, :language, :status, :source_file, :user_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:user_id)
  end
end
