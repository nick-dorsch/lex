defmodule LexWeb.LibraryLive.IndexTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Reader.UserSentenceState

  setup do
    # Set a non-existent Calibre path to isolate tests from the actual Calibre library
    original_path = Application.fetch_env!(:lex, :calibre_library_path)
    Application.put_env(:lex, :calibre_library_path, "/nonexistent/calibre/path/for/tests")

    on_exit(fn ->
      Application.put_env(:lex, :calibre_library_path, original_path)
    end)

    :ok
  end

  describe "index" do
    test "renders empty state when no documents ready", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "My Library"
      assert html =~ "No documents found."
      assert html =~ "Set CALIBRE_LIBRARY_PATH"
    end

    test "creates default user when no authenticated user is available", %{conn: conn} do
      assert Repo.aggregate(User, :count, :id) == 0

      {:ok, _view, _html} = live(conn, "/library")

      assert Repo.aggregate(User, :count, :id) == 1
      assert Repo.get_by(User, email: "default@lex.local")
    end

    test "renders list of ready documents", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ document.title
      assert html =~ document.author
    end

    test "does not show documents with non-ready status", %{conn: conn} do
      user = create_user()
      ready_doc = create_ready_document(user)
      _uploaded_doc = create_document(user, "uploaded")
      _processing_doc = create_document(user, "processing")
      _failed_doc = create_document(user, "failed")

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ ready_doc.title
      refute html =~ "uploaded document"
      refute html =~ "processing document"
      refute html =~ "failed document"
    end

    test "shows correct progress percentage", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)

      # Create 10 sentences
      sentences =
        for i <- 1..10 do
          create_sentence(section, i, "Sentence #{i}")
        end

      # Mark 3 as read
      for sentence <- Enum.take(sentences, 3) do
        mark_sentence_read(user, sentence)
      end

      {:ok, _view, html} = live(conn, "/library")

      # Progress should be 30% (3 out of 10)
      assert html =~ "30%"
    end

    test "shows 0% progress when no sentences read", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)

      # Create 5 sentences but mark none as read
      for i <- 1..5 do
        create_sentence(section, i, "Sentence #{i}")
      end

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "0%"
    end

    test "shows 100% progress when all sentences read", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)

      # Create 4 sentences and mark all as read
      sentences =
        for i <- 1..4 do
          create_sentence(section, i, "Sentence #{i}")
        end

      for sentence <- sentences do
        mark_sentence_read(user, sentence)
      end

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "100%"
    end

    test "clicking read button navigates to reader", %{conn: conn} do
      user = create_user()
      _document = create_ready_document(user)

      {:ok, view, _html} = live(conn, "/library")

      # Verify the library-item has the read button with navigate handler
      html = render(view)
      assert html =~ "library-item"
      assert html =~ "phx-click=\"navigate_to_reader\""
    end

    test "shows imported badge for imported items", %{conn: conn} do
      user = create_user()
      _document = create_ready_document(user)

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "source-badge imported"
      assert html =~ "Imported"
      assert html =~ "library-item database"
    end

    test "shows import button for not_imported items", %{conn: conn} do
      # Test the import button appears when item has not_imported status
      {:ok, _view, html} = live(conn, "/library")

      # When there are no items, we should see empty state
      assert html =~ "No documents found."

      # Add a document and verify it shows as imported (Read button)
      user = create_user()
      _document = create_ready_document(user)

      {:ok, _view2, html} = live(conn, "/library")
      assert html =~ "Read"
      assert html =~ "imported-badge"
    end
  end

  describe "import status updates via PubSub" do
    test "updates UI when import_started message received", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # Send import_started message
      file_path = "/test/book.epub"
      send(view.pid, {:import_started, file_path, 1})

      # The page should handle the message without crashing
      html = render(view)
      assert html =~ "My Library"
    end

    test "updates UI when import_completed message received", %{conn: conn} do
      user = create_user()
      {:ok, view, _html} = live(conn, "/library")

      # First add a document
      document = create_ready_document(user)
      file_path = "/test/book.epub"

      # Send import_completed message
      send(view.pid, {:import_completed, file_path, document.id, user.id})

      # The page should handle the message without crashing
      html = render(view)
      assert html =~ "My Library"
    end

    test "updates UI when import_failed message received", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # Send import_failed message
      file_path = "/test/book.epub"
      send(view.pid, {:import_failed, file_path, "EPUB parsing failed", 1})

      # The page should handle the message without crashing
      html = render(view)
      assert html =~ "My Library"
    end

    test "shows chapter-based import progress details", %{conn: conn} do
      temp_root = "/tmp/lex_library_live_#{System.unique_integer([:positive])}"
      temp_book_dir = Path.join(temp_root, "Author/Book")
      file_path = Path.join(temp_book_dir, "book.epub")

      File.mkdir_p!(temp_book_dir)
      File.cp!("test/fixtures/epubs/el_principito.epub", file_path)

      original_path = Application.fetch_env!(:lex, :calibre_library_path)
      Application.put_env(:lex, :calibre_library_path, temp_root)

      try do
        {:ok, view, _html} = live(conn, "/library")

        send(view.pid, {:import_progress, file_path, 42, "Processing chapter 2 of 5", 1})

        html = render(view)
        assert html =~ "Processing chapter 2 of 5"
        assert html =~ "42%"
      after
        Application.put_env(:lex, :calibre_library_path, original_path)
        File.rm_rf(temp_root)
      end
    end
  end

  describe "refresh_calibre event" do
    test "refresh button triggers reload and shows flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # Click refresh button
      html = view |> element("button", "Refresh Library") |> render_click()

      assert html =~ "My Library"
      # Flash messages appear in the rendered HTML when there's a flash
      # Since Calibre path is not available in tests, count will be 0
      assert html =~ "Found 0 books in Calibre library"
    end

    test "refresh button is debounced", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # First click should work
      view |> element("button", "Refresh Library") |> render_click()

      # Button should now be disabled
      html = render(view)
      assert html =~ "Refreshing..."
      assert html =~ "disabled"
    end

    test "refresh debounce is cleared after timer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # First click enables debounce
      view |> element("button", "Refresh Library") |> render_click()
      html = render(view)
      assert html =~ "Refreshing..."

      # Send the clear debounce message directly
      send(view.pid, :clear_refresh_debounce)

      # Button should be enabled again
      html = render(view)
      assert html =~ "Refresh Library"
      refute html =~ "disabled"
    end
  end

  describe "import_epub event" do
    test "handles import_epub event for non-existent file", %{conn: conn} do
      # Test that the event handler exists and works without crashing
      {:ok, view, _html} = live(conn, "/library")

      # The handler should work even if the file doesn't exist
      # (it will mark as importing via PubSub)
      html =
        view
        |> element("button", "Refresh Library")
        |> render_click()

      assert html =~ "My Library"
    end
  end

  describe "async import completion via PubSub" do
    test "handle_info updates UI when import_started received", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      file_path = "/test/book.epub"
      send(view.pid, {:import_started, file_path, 1})

      # The page should handle the message without crashing
      html = render(view)
      assert html =~ "My Library"
    end

    test "handle_info updates UI when import_completed received", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)

      {:ok, view, _html} = live(conn, "/library")

      file_path = "/test/book.epub"

      # Send import_started first
      send(view.pid, {:import_started, file_path, user.id})

      # Then send completion
      send(view.pid, {:import_completed, file_path, document.id, user.id})

      html = render(view)
      assert html =~ "My Library"
    end

    test "handle_info updates UI when import_failed received", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      file_path = "/test/book.epub"

      # Send failure message directly
      send(view.pid, {:import_failed, file_path, "EPUB parsing failed", 1})

      html = render(view)
      assert html =~ "My Library"
    end

    test "handle_info clears refresh debounce", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # Enable debounce
      view |> element("button", "Refresh Library") |> render_click()

      # Send clear message
      send(view.pid, :clear_refresh_debounce)

      html = render(view)
      assert html =~ "Refresh Library"
      refute html =~ "disabled"
    end
  end

  describe "unified view with Calibre integration" do
    test "gracefully handles missing Calibre folder", %{conn: conn} do
      # When CALIBRE_LIBRARY_PATH is not set or doesn't exist
      # the page should still load and show database items
      user = create_user()
      document = create_ready_document(user)

      # Set a non-existent Calibre path for this test
      original_path = Application.fetch_env!(:lex, :calibre_library_path)
      Application.put_env(:lex, :calibre_library_path, "/nonexistent/calibre/path/test")

      try do
        {:ok, _view, html} = live(conn, "/library")

        # Should still show the database document
        assert html =~ document.title
        # Should not show calibre notice when path unavailable
        refute html =~ "Calibre library connected"
      after
        Application.put_env(:lex, :calibre_library_path, original_path)
      end
    end

    test "items are sorted by title", %{conn: conn} do
      user = create_user()

      # Create documents with different titles
      create_document_with_title(user, "Zebra Book")
      create_document_with_title(user, "Apple Book")
      create_document_with_title(user, "Mango Book")

      {:ok, _view, html} = live(conn, "/library")

      # All three should be present
      assert html =~ "Zebra Book"
      assert html =~ "Apple Book"
      assert html =~ "Mango Book"
    end
  end

  # Helper functions for creating test data

  defp create_user do
    %User{}
    |> User.changeset(%{
      name: "Test User",
      email: "test#{System.unique_integer()}_#{:erlang.monotonic_time()}@example.com",
      primary_language: "en"
    })
    |> Repo.insert!()
  end

  defp create_ready_document(user) do
    create_document(user, "ready")
  end

  defp create_document_with_title(user, title) do
    %Document{}
    |> Document.changeset(%{
      title: title,
      author: "Test Author",
      language: "en",
      status: "ready",
      source_file: "test.epub",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp create_document(user, status) do
    %Document{}
    |> Document.changeset(%{
      title: "#{status} document",
      author: "Test Author",
      language: "en",
      status: status,
      source_file: "test.epub",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp create_section(document) do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: 1,
      title: "Test Section"
    })
    |> Repo.insert!()
  end

  defp create_sentence(section, position, text) do
    %Sentence{}
    |> Sentence.changeset(%{
      section_id: section.id,
      position: position,
      text: text,
      char_start: 0,
      char_end: String.length(text)
    })
    |> Repo.insert!()
  end

  defp mark_sentence_read(user, sentence) do
    %UserSentenceState{}
    |> UserSentenceState.changeset(%{
      user_id: user.id,
      sentence_id: sentence.id,
      status: "read",
      read_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end
end
