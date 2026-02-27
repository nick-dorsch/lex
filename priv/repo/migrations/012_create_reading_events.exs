defmodule Lex.Repo.Migrations.CreateReadingEvents do
  use Ecto.Migration

  def change do
    create table(:reading_events) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:document_id, references(:documents, on_delete: :delete_all), null: false)
      add(:sentence_id, references(:sentences, on_delete: :nilify_all))
      add(:token_id, references(:tokens, on_delete: :nilify_all))
      add(:event_type, :string, null: false)
      add(:payload, :text, null: false)

      timestamps(updated_at: false)
    end

    create(index(:reading_events, [:user_id]))
    create(index(:reading_events, [:document_id]))
    create(index(:reading_events, [:sentence_id]))
    create(index(:reading_events, [:token_id]))
    create(index(:reading_events, [:event_type]))
    create(index(:reading_events, [:user_id, :document_id, :event_type]))
    create(index(:reading_events, [:inserted_at]))
    create(index(:reading_events, [:user_id, :document_id, :inserted_at]))
  end
end
