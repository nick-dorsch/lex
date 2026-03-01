defmodule LexWeb.LibraryLive.Index do
  use LexWeb, :live_view

  alias Lex.Repo
  alias Lex.Library.Document
  alias Lex.Text.Sentence
  alias Lex.Reader.UserSentenceState

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # For now, get current user from socket or use a default
    # In a real app, this would come from authentication
    user_id = get_user_id(socket)

    documents = list_ready_documents_with_progress(user_id)

    {:ok, assign(socket, :documents, documents)}
  end

  @impl true
  def handle_event("navigate_to_reader", %{"document_id" => document_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/read/#{document_id}")}
  end

  defp get_user_id(_socket) do
    # Placeholder - in a real app, this would get the user from session/token
    # For now, we'll query all documents and filter in the query
    nil
  end

  defp list_ready_documents_with_progress(user_id) do
    # Query documents with status "ready"
    documents =
      Document
      |> where(status: "ready")
      |> Repo.all()

    # For each document, calculate progress
    Enum.map(documents, fn document ->
      progress = calculate_progress(document.id, user_id)
      Map.put(document, :progress, progress)
    end)
  end

  defp calculate_progress(document_id, user_id) do
    # Get total sentences for this document
    total_query =
      from(s in Sentence,
        join: sec in assoc(s, :section),
        where: sec.document_id == ^document_id,
        select: count(s.id)
      )

    total = Repo.one(total_query) || 0

    # Get read sentences for this user and document
    read_query =
      from(uss in UserSentenceState,
        join: s in assoc(uss, :sentence),
        join: sec in assoc(s, :section),
        where: sec.document_id == ^document_id,
        where: uss.user_id == ^user_id,
        where: uss.status == "read",
        select: count(uss.id)
      )

    read = Repo.one(read_query) || 0

    if total > 0 do
      round(read / total * 100)
    else
      0
    end
  end
end
