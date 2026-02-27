defmodule Lex.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def change do
    create table(:tokens) do
      add(:sentence_id, references(:sentences, on_delete: :delete_all), null: false)
      add(:position, :integer, null: false)
      add(:surface, :string, null: false)
      add(:normalized_surface, :string, null: false)
      add(:lemma, :string, null: false)
      add(:pos, :string, null: false)
      add(:is_punctuation, :boolean, default: false, null: false)
      add(:char_start, :integer)
      add(:char_end, :integer)
      add(:lexeme_id, references(:lexemes, on_delete: :nilify_all))

      timestamps()
    end

    create(index(:tokens, [:sentence_id]))
    create(index(:tokens, [:lexeme_id]))
    create(unique_index(:tokens, [:sentence_id, :position]))
    create(index(:tokens, [:is_punctuation]))
    create(index(:tokens, [:lemma]))
  end
end
