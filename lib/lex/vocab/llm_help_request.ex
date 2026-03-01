defmodule Lex.Vocab.LlmHelpRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_request_types ["sentence", "token"]

  @type t :: %__MODULE__{
          id: integer() | nil,
          request_type: String.t(),
          response_language: String.t(),
          provider: String.t(),
          model: String.t(),
          latency_ms: integer() | nil,
          prompt_tokens: integer() | nil,
          completion_tokens: integer() | nil,
          response_text: String.t() | nil,
          user_id: integer(),
          document_id: integer(),
          sentence_id: integer(),
          token_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "llm_help_requests" do
    field(:request_type, :string)
    field(:response_language, :string)
    field(:provider, :string)
    field(:model, :string)
    field(:latency_ms, :integer)
    field(:prompt_tokens, :integer)
    field(:completion_tokens, :integer)
    field(:response_text, :string)

    belongs_to(:user, Lex.Accounts.User)
    belongs_to(:document, Lex.Library.Document)
    belongs_to(:sentence, Lex.Text.Sentence)
    belongs_to(:token, Lex.Text.Token)

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(llm_help_request, attrs) do
    llm_help_request
    |> cast(attrs, [
      :user_id,
      :document_id,
      :sentence_id,
      :token_id,
      :request_type,
      :response_language,
      :provider,
      :model,
      :latency_ms,
      :prompt_tokens,
      :completion_tokens,
      :response_text
    ])
    |> validate_required([
      :user_id,
      :document_id,
      :sentence_id,
      :request_type,
      :response_language,
      :provider,
      :model
    ])
    |> validate_inclusion(:request_type, @valid_request_types)
    |> validate_number(:latency_ms, greater_than_or_equal_to: 0)
    |> validate_number(:prompt_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:completion_tokens, greater_than_or_equal_to: 0)
    |> validate_token_id_for_request_type()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:sentence_id)
    |> foreign_key_constraint(:token_id)
  end

  defp validate_token_id_for_request_type(changeset) do
    request_type = get_field(changeset, :request_type)
    token_id = get_field(changeset, :token_id)

    cond do
      request_type == "sentence" and not is_nil(token_id) ->
        add_error(changeset, :token_id, "must be nil for sentence-level requests")

      request_type == "token" and is_nil(token_id) ->
        add_error(changeset, :token_id, "is required for token-level requests")

      true ->
        changeset
    end
  end
end
