defmodule Lex.Reader.ReadingEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_event_types [
    "enter_sentence",
    "advance_sentence",
    "retreat_sentence",
    "skip_range",
    "mark_learning",
    "unmark_learning",
    "llm_help_requested"
  ]

  schema "reading_events" do
    field(:event_type, :string)
    field(:payload, :string)

    belongs_to(:user, Lex.Accounts.User)
    belongs_to(:document, Lex.Library.Document)
    belongs_to(:sentence, Lex.Text.Sentence)
    belongs_to(:token, Lex.Text.Token)

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(reading_event, attrs) do
    reading_event
    |> cast(attrs, [
      :user_id,
      :document_id,
      :sentence_id,
      :token_id,
      :event_type,
      :payload
    ])
    |> validate_required([:user_id, :document_id, :event_type, :payload])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_payload_json()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:sentence_id)
    |> foreign_key_constraint(:token_id)
  end

  defp validate_payload_json(changeset) do
    case get_field(changeset, :payload) do
      nil ->
        changeset

      payload when is_binary(payload) ->
        case Jason.decode(payload) do
          {:ok, _} -> changeset
          {:error, _} -> add_error(changeset, :payload, "must be valid JSON")
        end

      _ ->
        add_error(changeset, :payload, "must be a string")
    end
  end

  @doc """
  Encodes a map to JSON string for the payload field.
  """
  def encode_payload(payload_map) when is_map(payload_map) do
    Jason.encode!(payload_map)
  end

  @doc """
  Decodes the payload JSON string to a map.
  """
  def decode_payload(%__MODULE__{payload: payload}) when is_binary(payload) do
    Jason.decode!(payload)
  end

  def decode_payload(payload) when is_binary(payload) do
    Jason.decode!(payload)
  end
end
