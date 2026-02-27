defmodule Lex.Repo.Migrations.CreateUserLexemeStates do
  use Ecto.Migration

  def change do
    create table(:user_lexeme_states) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:lexeme_id, references(:lexemes, on_delete: :delete_all), null: false)
      add(:status, :string, null: false)
      add(:seen_count, :integer, null: false, default: 0)
      add(:first_seen_at, :utc_datetime, null: true)
      add(:last_seen_at, :utc_datetime, null: true)
      add(:known_at, :utc_datetime, null: true)
      add(:learning_since, :utc_datetime, null: true)

      timestamps()
    end

    create(unique_index(:user_lexeme_states, [:user_id, :lexeme_id]))
    create(index(:user_lexeme_states, [:user_id]))
    create(index(:user_lexeme_states, [:lexeme_id]))
    create(index(:user_lexeme_states, [:status]))
    create(index(:user_lexeme_states, [:user_id, :status]))
    create(index(:user_lexeme_states, [:user_id, :status, :lexeme_id]))
  end
end
