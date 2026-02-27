defmodule Lex.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:primary_language, :string, null: false)

      timestamps()
    end

    create(unique_index(:users, [:email]))
    create(index(:users, [:primary_language]))
  end
end
