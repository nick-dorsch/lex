defmodule Lex.Repo.Migrations.CreateUserSentenceStates do
  use Ecto.Migration

  def change do
    create table(:user_sentence_states) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:sentence_id, references(:sentences, on_delete: :delete_all), null: false)
      add(:status, :string, null: false)
      add(:read_at, :utc_datetime, null: true)

      timestamps()
    end

    create(unique_index(:user_sentence_states, [:user_id, :sentence_id]))
    create(index(:user_sentence_states, [:user_id]))
    create(index(:user_sentence_states, [:sentence_id]))
    create(index(:user_sentence_states, [:status]))
    create(index(:user_sentence_states, [:user_id, :status]))
    create(index(:user_sentence_states, [:user_id, :sentence_id, :status]))
  end
end
