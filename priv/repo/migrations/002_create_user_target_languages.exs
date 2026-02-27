defmodule Lex.Repo.Migrations.CreateUserTargetLanguages do
  use Ecto.Migration

  def change do
    create table(:user_target_languages) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:language_code, :string, null: false)

      timestamps()
    end

    create(index(:user_target_languages, [:user_id]))
    create(unique_index(:user_target_languages, [:user_id, :language_code]))
  end
end
