defmodule LexWeb.ReaderLive.Show do
  use LexWeb, :live_view

  alias Lex.Repo
  alias Lex.Reader
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Text.Token

  import Ecto.Query

  @impl true
  def mount(%{"document_id" => document_id}, _session, socket) do
    user_id = 1

    case load_reader_data(user_id, document_id) do
      {:ok, %{document: document, section: section, sentence: sentence, tokens: tokens}} ->
        {:ok,
         assign(socket,
           document: document,
           section: section,
           sentence: sentence,
           tokens: tokens,
           loading: false
         )}

      {:error, :document_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Document not found")
         |> redirect(to: ~p"/library")}
    end
  end

  defp load_reader_data(user_id, document_id) do
    with {:ok, position} <- Reader.get_or_create_position(user_id, document_id),
         document when not is_nil(document) <- Repo.get(Document, document_id) do
      section = position.section_id && Repo.get(Section, position.section_id)
      sentence = position.sentence_id && Repo.get(Sentence, position.sentence_id)

      tokens =
        if sentence do
          load_tokens(sentence.id)
        else
          []
        end

      {:ok,
       %{
         document: document,
         section: section,
         sentence: sentence,
         tokens: tokens
       }}
    else
      {:error, :document_not_found} -> {:error, :document_not_found}
      nil -> {:error, :document_not_found}
    end
  end

  defp load_tokens(sentence_id) do
    Token
    |> where(sentence_id: ^sentence_id)
    |> order_by(asc: :position)
    |> Repo.all()
  end
end
