defmodule Lex.Repo.Migrations.CreateSections do
  use Ecto.Migration

  def change do
    create table(:sections) do
      add(:document_id, references(:documents, on_delete: :delete_all), null: false)
      add(:position, :integer, null: false)
      add(:title, :string)
      add(:source_href, :string)

      timestamps()
    end

    create(index(:sections, [:document_id]))
    create(unique_index(:sections, [:document_id, :position]))
  end
end
