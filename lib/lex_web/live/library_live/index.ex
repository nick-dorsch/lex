defmodule LexWeb.LibraryLive.Index do
  @moduledoc """
  LiveView for the library index page showing unified view of
  Calibre files and imported documents.
  """
  use LexWeb, :live_view

  alias Lex.Repo
  alias Lex.Library
  alias Lex.Library.{CalibreScanner, Document, ImportTracker, ImportWorker}
  alias Lex.Text.Sentence
  alias Lex.Reader.UserSentenceState
  alias Phoenix.PubSub

  import Ecto.Query

  require Logger

  @type unified_item :: %{
          id: String.t() | integer(),
          title: String.t(),
          author: String.t(),
          source: :calibre | :database,
          import_status: :not_imported | :importing | :imported | :error,
          document_id: integer() | nil,
          error: String.t() | nil,
          progress: integer() | nil
        }

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_user_id(socket)

    # Subscribe to import updates for this user
    PubSub.subscribe(Lex.PubSub, ImportTracker.topic(user_id))

    # Load unified library view
    items = load_unified_library(user_id)

    {:ok,
     socket
     |> assign(:items, items)
     |> assign(:user_id, user_id)
     |> assign(:calibre_available, calibre_available?())}
  end

  @impl true
  def handle_info({:import_started, file_path, _user_id}, socket) do
    items =
      Enum.map(socket.assigns.items, fn item ->
        if to_string(item.id) == file_path do
          %{item | import_status: :importing, error: nil}
        else
          item
        end
      end)

    {:noreply, assign(socket, :items, items)}
  end

  @impl true
  def handle_info({:import_completed, file_path, document_id, _user_id}, socket) do
    # Fetch the newly created document to get its details
    document = Repo.get(Document, document_id)

    items =
      Enum.map(socket.assigns.items, fn item ->
        if to_string(item.id) == file_path do
          %{
            item
            | import_status: :imported,
              document_id: document_id,
              error: nil,
              title: if(document, do: document.title, else: item.title),
              author: if(document, do: document.author || "Unknown", else: item.author)
          }
        else
          item
        end
      end)

    {:noreply, assign(socket, :items, items)}
  end

  @impl true
  def handle_info({:import_failed, file_path, reason, _user_id}, socket) do
    items =
      Enum.map(socket.assigns.items, fn item ->
        if to_string(item.id) == file_path do
          %{item | import_status: :error, error: reason}
        else
          item
        end
      end)

    {:noreply, assign(socket, :items, items)}
  end

  @impl true
  def handle_event("navigate_to_reader", %{"document_id" => document_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/read/#{document_id}")}
  end

  @impl true
  def handle_event("import", %{"file_path" => file_path}, socket) do
    user_id = socket.assigns.user_id

    # Start the import in the background
    case ImportTracker.start_import(file_path, user_id) do
      :ok ->
        ImportWorker.start_import(file_path, user_id)

        # Update the local state immediately for UI feedback
        items =
          Enum.map(socket.assigns.items, fn item ->
            if item.id == file_path do
              %{item | import_status: :importing}
            else
              item
            end
          end)

        {:noreply, assign(socket, :items, items)}

      :already_importing ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    items = load_unified_library(socket.assigns.user_id)
    {:noreply, assign(socket, :items, items)}
  end

  defp get_user_id(_socket) do
    1
  end

  defp calibre_available? do
    path = Library.calibre_library_path()
    not is_nil(path) and path != "" and File.exists?(path)
  end

  @spec load_unified_library(integer()) :: [unified_item()]
  defp load_unified_library(user_id) do
    # Get Calibre items
    calibre_items =
      case CalibreScanner.scan() do
        {:ok, books} ->
          Enum.map(books, &calibre_book_to_unified_item/1)

        {:error, _reason} ->
          []
      end

    # Get database items (ready documents that aren't from Calibre)
    db_items =
      Document
      |> where(status: "ready")
      |> Repo.all()
      |> Enum.map(&document_to_unified_item(&1, user_id))

    # Merge and deduplicate
    # Calibre items take precedence if there's a document_id match
    merged = merge_items(calibre_items, db_items)

    # Sort by title
    Enum.sort_by(merged, & &1.title, :asc)
  end

  @spec calibre_book_to_unified_item(CalibreScanner.t()) :: unified_item()
  defp calibre_book_to_unified_item(book) do
    %{
      id: book.file_path,
      title: book.title,
      author: book.author,
      source: :calibre,
      import_status: book.import_status,
      document_id: book.document_id,
      error: nil,
      progress: nil
    }
  end

  @spec document_to_unified_item(Document.t(), integer()) :: unified_item()
  defp document_to_unified_item(document, user_id) do
    progress = calculate_progress(document.id, user_id)

    %{
      id: document.id,
      title: document.title,
      author: document.author || "Unknown",
      source: :database,
      import_status: :imported,
      document_id: document.id,
      error: nil,
      progress: progress
    }
  end

  @spec merge_items([unified_item()], [unified_item()]) :: [unified_item()]
  defp merge_items(calibre_items, db_items) do
    # Create a map of document_id -> db_item for quick lookup
    db_items_by_id =
      Enum.reduce(db_items, %{}, fn item, acc ->
        Map.put(acc, item.document_id, item)
      end)

    # Process Calibre items
    {merged_calibre, matched_doc_ids} =
      Enum.reduce(calibre_items, {[], MapSet.new()}, fn calibre_item, {items, matched} ->
        case calibre_item.document_id do
          nil ->
            # Not imported, keep the Calibre item
            {[calibre_item | items], matched}

          doc_id ->
            # Has a matching document, enrich with progress from DB item
            db_item = Map.get(db_items_by_id, doc_id)

            enriched_item =
              if db_item do
                %{calibre_item | progress: db_item.progress}
              else
                calibre_item
              end

            {[enriched_item | items], MapSet.put(matched, doc_id)}
        end
      end)

    # Add DB items that don't have a Calibre counterpart
    unmatched_db_items =
      Enum.reject(db_items, fn item ->
        MapSet.member?(matched_doc_ids, item.document_id)
      end)

    merged_calibre ++ unmatched_db_items
  end

  defp calculate_progress(_document_id, nil) do
    0
  end

  defp calculate_progress(document_id, user_id) do
    total_query =
      from(s in Sentence,
        join: sec in assoc(s, :section),
        where: sec.document_id == ^document_id,
        select: count(s.id)
      )

    total = Repo.one(total_query) || 0

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
