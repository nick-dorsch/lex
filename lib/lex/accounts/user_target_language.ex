defmodule Lex.Accounts.UserTargetLanguage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_target_languages" do
    field(:language_code, :string)

    belongs_to(:user, Lex.Accounts.User)

    timestamps()
  end

  @doc false
  def changeset(user_target_language, attrs) do
    user_target_language
    |> cast(attrs, [:user_id, :language_code])
    |> validate_required([:user_id, :language_code])
    |> unique_constraint([:user_id, :language_code])
  end
end
