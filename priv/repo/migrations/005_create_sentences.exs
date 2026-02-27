defmodule Lex.Repo.Migrations.CreateSentences do
  use Ecto.Migration

  def change do
    create table(:sentences) do
      add(:section_id, references(:sections, on_delete: :delete_all), null: false)
      add(:position, :integer, null: false)
      add(:text, :text, null: false)
      add(:char_start, :integer)
      add(:char_end, :integer)

      timestamps()
    end

    create(index(:sentences, [:section_id]))
    create(unique_index(:sentences, [:section_id, :position]))
  end
end
