defmodule LexWeb.LibraryLive.Index do
  @moduledoc """
  LiveView for the library index page showing unified view of
  Calibre files and imported documents.
  """
  use LexWeb, :live_view

  alias Lex.Accounts.User
  alias Lex.Accounts.UserTargetLanguage
  alias Lex.Repo
  alias Lex.Library
  alias Lex.Library.{CalibreScanner, Document, ImportTracker, Language}
  alias Lex.Text.Sentence
  alias Lex.Reader.UserSentenceState
  alias Phoenix.PubSub

  import Ecto.Query

  require Logger

  @type unified_item :: %{
          id: String.t() | integer(),
          title: String.t(),
          author: String.t(),
          language: String.t() | nil,
          cover_token: String.t() | nil,
          source: :calibre | :database,
          import_status: :not_imported | :importing | :imported | :error,
          document_id: integer() | nil,
          error: String.t() | nil,
          progress: integer() | nil,
          import_percent: integer() | nil,
          import_stage: String.t() | nil
        }

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_user_id(socket)

    subscribe_to_import_updates(user_id)

    items = if user_id, do: load_unified_library(user_id), else: []

    {:ok,
     socket
     |> assign(:items, items)
     |> assign(:user_id, user_id)
     |> assign(:calibre_available, calibre_available?())
     |> assign(:refreshing, false)
     |> assign_profile_setup_state(user_id)}
  end

  @impl true
  def handle_info({:import_started, file_path, _user_id}, socket) do
    items =
      Enum.map(socket.assigns.items, fn item ->
        if to_string(item.id) == file_path do
          %{
            item
            | import_status: :importing,
              error: nil,
              import_percent: 0,
              import_stage: "Queued import"
          }
        else
          item
        end
      end)

    {:noreply, assign(socket, :items, items)}
  end

  @impl true
  def handle_info({:import_progress, file_path, percent, stage, _user_id}, socket) do
    items =
      Enum.map(socket.assigns.items, fn item ->
        if to_string(item.id) == file_path do
          %{
            item
            | import_status: :importing,
              error: nil,
              import_percent: percent,
              import_stage: stage
          }
        else
          item
        end
      end)

    {:noreply, assign(socket, :items, items)}
  end

  @impl true
  def handle_info(:clear_refresh_debounce, socket) do
    {:noreply, assign(socket, :refreshing, false)}
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
              import_percent: nil,
              import_stage: nil,
              title: if(document, do: document.title, else: item.title),
              author: if(document, do: document.author || "Unknown", else: item.author)
          }
        else
          item
        end
      end)

    title = if document, do: document.title, else: "Book"

    {:noreply,
     socket
     |> assign(:items, items)
     |> put_flash(:info, "'#{title}' imported successfully")}
  end

  @impl true
  def handle_info({:import_failed, file_path, reason, _user_id}, socket) do
    items =
      Enum.map(socket.assigns.items, fn item ->
        if to_string(item.id) == file_path do
          %{item | import_status: :error, error: reason, import_percent: nil, import_stage: nil}
        else
          item
        end
      end)

    {:noreply,
     socket
     |> assign(:items, items)
     |> put_flash(:error, "Import failed: #{reason}")}
  end

  @impl true
  def handle_event("navigate_to_reader", %{"document_id" => document_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/read/#{document_id}")}
  end

  @impl true
  def handle_event("import_epub", %{"file_path" => file_path}, socket) do
    user_id = socket.assigns.user_id

    # Start the import in the background
    case Library.import_epub_async(file_path, user_id) do
      {:ok, :started} ->
        # Update the local state immediately for UI feedback
        items =
          Enum.map(socket.assigns.items, fn item ->
            if item.id == file_path do
              %{
                item
                | import_status: :importing,
                  error: nil,
                  import_percent: 0,
                  import_stage: "Queued import"
              }
            else
              item
            end
          end)

        {:noreply,
         socket
         |> assign(:items, items)
         |> put_flash(:info, "Import started...")}

      {:ok, :already_importing} ->
        {:noreply, put_flash(socket, :warning, "Import already in progress")}

      {:ok, :already_imported} ->
        {:noreply, put_flash(socket, :info, "Book already imported")}
    end
  end

  @impl true
  def handle_event("refresh_calibre", _params, socket) do
    # Debounce: prevent rapid clicking
    if socket.assigns.refreshing do
      {:noreply, socket}
    else
      user_id = socket.assigns.user_id

      # Re-scan Calibre library (this will automatically clear stale states)
      items = load_unified_library(user_id)

      # Count Calibre books
      calibre_count =
        items
        |> Enum.filter(&(&1.source == :calibre))
        |> length()

      # Start timer to clear debounce flag after 2 seconds
      Process.send_after(self(), :clear_refresh_debounce, 2000)

      {:noreply,
       socket
       |> assign(:items, items)
       |> assign(:refreshing, true)
       |> put_flash(:info, "Found #{calibre_count} books in Calibre library")}
    end
  end

  @impl true
  def handle_event("validate_profile_setup", %{"profile" => profile_params}, socket) do
    user = load_user(socket.assigns.user_id)
    params = normalize_profile_params(profile_params)

    {:noreply,
     socket
     |> assign(:profile_params, params)
     |> assign(:profile_changeset, profile_changeset(user, params, :validate))}
  end

  @impl true
  def handle_event("save_profile_setup", %{"profile" => profile_params}, socket) do
    user = load_user(socket.assigns.user_id)
    params = normalize_profile_params(profile_params)
    changeset = profile_changeset(user, params, :validate)

    if changeset.valid? do
      case save_profile_setup(user, params) do
        {:ok, updated_user} ->
          maybe_subscribe_to_import_updates(socket.assigns.user_id, updated_user.id)

          {:noreply,
           socket
           |> assign(:user_id, updated_user.id)
           |> assign(:items, load_unified_library(updated_user.id))
           |> assign(:show_profile_setup_modal, false)
           |> put_flash(:info, "Profile setup complete")}

        {:error, %Ecto.Changeset{} = error_changeset} ->
          {:noreply,
           socket
           |> assign(:profile_params, params)
           |> assign(:profile_changeset, Map.put(error_changeset, :action, :validate))}
      end
    else
      {:noreply,
       socket
       |> assign(:profile_params, params)
       |> assign(:profile_changeset, changeset)}
    end
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} -> user_id
      _ -> first_user_id()
    end
  end

  defp first_user_id,
    do: Repo.one(from(u in User, order_by: [asc: u.id], limit: 1, select: u.id))

  defp subscribe_to_import_updates(nil), do: :ok

  defp subscribe_to_import_updates(user_id) do
    PubSub.subscribe(Lex.PubSub, ImportTracker.topic(user_id))
  end

  defp maybe_subscribe_to_import_updates(current_user_id, new_user_id)
       when is_nil(current_user_id) and is_integer(new_user_id) do
    subscribe_to_import_updates(new_user_id)
  end

  defp maybe_subscribe_to_import_updates(_current_user_id, _new_user_id), do: :ok

  defp load_user(nil), do: nil
  defp load_user(user_id), do: Repo.get(User, user_id)

  defp calibre_available? do
    path = Library.calibre_library_path()
    not is_nil(path) and path != "" and File.exists?(path)
  end

  defp assign_profile_setup_state(socket, user_id) do
    user = load_user(user_id)
    target_languages = load_target_languages(user_id)
    params = default_profile_params(user, target_languages)

    socket
    |> assign(:show_profile_setup_modal, requires_profile_setup?(user, target_languages))
    |> assign(:profile_params, params)
    |> assign(:profile_changeset, profile_changeset(user, params, nil))
    |> assign(:target_language_options, target_language_options())
  end

  defp requires_profile_setup?(nil, _target_languages), do: true

  defp requires_profile_setup?(user, target_languages) do
    blank?(user.name) or blank?(user.email) or target_languages == [] or invalid_email?(user)
  end

  defp invalid_email?(user) do
    changeset =
      User.changeset(user, %{
        name: user.name,
        email: user.email,
        primary_language: user.primary_language
      })

    Keyword.has_key?(changeset.errors, :email)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp default_profile_params(nil, target_languages) do
    %{
      "name" => "",
      "email" => "",
      "target_languages" => target_languages
    }
  end

  defp default_profile_params(user, target_languages) do
    %{
      "name" => user.name || "",
      "email" => user.email || "",
      "target_languages" => target_languages
    }
  end

  defp normalize_profile_params(profile_params) do
    %{
      "name" => String.trim(Map.get(profile_params, "name", "")),
      "email" => String.trim(Map.get(profile_params, "email", "")),
      "target_languages" =>
        normalize_target_languages(Map.get(profile_params, "target_languages", []))
    }
  end

  defp normalize_target_languages(target_languages) when is_binary(target_languages) do
    [target_languages]
    |> normalize_target_languages()
  end

  defp normalize_target_languages(target_languages) when is_list(target_languages) do
    target_languages
    |> Enum.map(&Language.from_user_target/1)
    |> Enum.reject(&(&1 == Language.unknown()))
    |> Enum.uniq()
  end

  defp normalize_target_languages(_target_languages), do: []

  defp profile_changeset(user, profile_params, action) do
    user = user || %User{}

    attrs = %{
      name: profile_params["name"],
      email: profile_params["email"],
      primary_language: user.primary_language || "en"
    }

    changeset =
      if action do
        User.changeset(user, attrs)
      else
        Ecto.Changeset.change(user, attrs)
      end

    changeset =
      if not is_nil(action) and profile_params["target_languages"] == [] do
        Ecto.Changeset.add_error(
          changeset,
          :target_languages,
          "select at least one target language"
        )
      else
        changeset
      end

    if action do
      Map.put(changeset, :action, action)
    else
      changeset
    end
  end

  defp load_target_languages(nil), do: []

  defp load_target_languages(user_id) do
    UserTargetLanguage
    |> where([utl], utl.user_id == ^user_id)
    |> order_by([utl], asc: utl.language_code)
    |> select([utl], utl.language_code)
    |> Repo.all()
  end

  defp save_profile_setup(user, profile_params) do
    user_attrs = %{
      name: profile_params["name"],
      email: profile_params["email"],
      primary_language: (user && user.primary_language) || "en"
    }

    target_languages = profile_params["target_languages"]

    Repo.transaction(fn ->
      case persist_profile_user(user, user_attrs) do
        {:ok, updated_user} ->
          case persist_target_languages(updated_user, target_languages) do
            {:ok, updated_user} -> updated_user
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, updated_user} -> {:ok, updated_user}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp persist_profile_user(nil, user_attrs),
    do: %User{} |> User.changeset(user_attrs) |> Repo.insert()

  defp persist_profile_user(user, user_attrs),
    do: user |> User.changeset(user_attrs) |> Repo.update()

  defp persist_target_languages(user, target_languages) do
    Repo.delete_all(from(utl in UserTargetLanguage, where: utl.user_id == ^user.id))

    Enum.reduce_while(target_languages, {:ok, user}, fn language_code, {:ok, user_acc} ->
      %UserTargetLanguage{}
      |> UserTargetLanguage.changeset(%{
        user_id: user.id,
        language_code: language_code
      })
      |> Repo.insert()
      |> case do
        {:ok, _target_language} -> {:cont, {:ok, user_acc}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp target_language_options do
    [
      {"English", "en"},
      {"Spanish", "es"},
      {"French", "fr"},
      {"German", "de"},
      {"Italian", "it"},
      {"Portuguese", "pt"},
      {"Japanese", "ja"},
      {"Korean", "ko"},
      {"Chinese", "zh"}
    ]
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
      language: book.language,
      cover_token: cover_token(book.cover_path),
      source: :calibre,
      import_status: book.import_status,
      document_id: book.document_id,
      error: nil,
      progress: nil,
      import_percent: nil,
      import_stage: nil
    }
  end

  @spec document_to_unified_item(Document.t(), integer()) :: unified_item()
  defp document_to_unified_item(document, user_id) do
    progress = calculate_progress(document.id, user_id)

    %{
      id: document.id,
      title: document.title,
      author: document.author || "Unknown",
      language: nil,
      cover_token: nil,
      source: :database,
      import_status: :imported,
      document_id: document.id,
      error: nil,
      progress: progress,
      import_percent: nil,
      import_stage: nil
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

  defp cover_token(nil), do: nil

  defp cover_token(cover_path) do
    Phoenix.Token.sign(LexWeb.Endpoint, "calibre_cover", cover_path)
  end

  defp show_language_badge?(item) do
    item.source == :calibre and item.import_status != :imported
  end

  defp language_badge_label(language) do
    normalized = Language.from_epub(language)

    if normalized == Language.unknown() do
      "Language Unknown"
    else
      "Language: #{normalized}"
    end
  end

  defp language_badge_class(language) do
    normalized = Language.from_epub(language)

    if normalized == Language.unknown() do
      "language-badge unknown"
    else
      "language-badge known"
    end
  end
end
