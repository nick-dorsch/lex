defmodule Lex.Repo.Migrations.CreateReadingPositions do
  use Ecto.Migration

  def change do
    create table(:reading_positions) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:document_id, references(:documents, on_delete: :delete_all), null: false)
      add(:section_id, references(:sections, on_delete: :nilify_all))
      add(:sentence_id, references(:sentences, on_delete: :nilify_all))
      add(:active_token_position, :integer)

      timestamps()
    end

    create(unique_index(:reading_positions, [:user_id, :document_id]))
    create(index(:reading_positions, [:user_id]))
    create(index(:reading_positions, [:document_id]))
    create(index(:reading_positions, [:user_id, :document_id, :sentence_id]))
  end
end
