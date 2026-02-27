defmodule Lex.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:title, :string, null: false)
      add(:author, :string)
      add(:language, :string, null: false)
      add(:status, :string, null: false)
      add(:source_file, :string, null: false)

      timestamps()
    end

    create(index(:documents, [:user_id]))
    create(index(:documents, [:status]))
    create(index(:documents, [:user_id, :status]))
    create(index(:documents, [:language]))
  end
end
