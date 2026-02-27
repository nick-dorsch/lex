defmodule Lex.Repo.Migrations.CreateLlmHelpRequests do
  use Ecto.Migration

  def change do
    create table(:llm_help_requests) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:document_id, references(:documents, on_delete: :delete_all), null: false)
      add(:sentence_id, references(:sentences, on_delete: :delete_all), null: false)
      add(:token_id, references(:tokens, on_delete: :nilify_all))
      add(:request_type, :string, null: false)
      add(:response_language, :string, null: false)
      add(:provider, :string, null: false)
      add(:model, :string, null: false)
      add(:latency_ms, :integer)
      add(:prompt_tokens, :integer)
      add(:completion_tokens, :integer)
      add(:response_text, :text)

      timestamps(updated_at: false)
    end

    create(index(:llm_help_requests, [:user_id]))
    create(index(:llm_help_requests, [:document_id]))
    create(index(:llm_help_requests, [:sentence_id]))
    create(index(:llm_help_requests, [:token_id]))
    create(index(:llm_help_requests, [:request_type]))
    create(index(:llm_help_requests, [:user_id, :document_id]))
    create(index(:llm_help_requests, [:inserted_at]))
    create(index(:llm_help_requests, [:sentence_id, :token_id, :response_language]))
  end
end
