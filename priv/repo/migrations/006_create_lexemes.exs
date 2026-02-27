defmodule Lex.Repo.Migrations.CreateLexemes do
  use Ecto.Migration

  def change do
    create table(:lexemes) do
      add(:language, :string, null: false)
      add(:lemma, :string, null: false)
      add(:normalized_lemma, :string, null: false)
      add(:pos, :string, null: false)

      timestamps()
    end

    create(unique_index(:lexemes, [:language, :normalized_lemma, :pos]))
    create(index(:lexemes, [:language]))
    create(index(:lexemes, [:normalized_lemma]))
    create(index(:lexemes, [:pos]))
  end
end
