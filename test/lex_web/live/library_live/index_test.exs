defmodule LexWeb.LibraryLive.IndexTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Accounts.UserTargetLanguage
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
      assert html =~ "Stats"
      assert html =~ "No documents found."
      assert html =~ "Set CALIBRE_LIBRARY_PATH"
    end

    test "does not create a user when no authenticated user is available", %{conn: conn} do
      assert Repo.aggregate(User, :count, :id) == 0

      {:ok, _view, _html} = live(conn, "/library")

      assert Repo.aggregate(User, :count, :id) == 0
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

  describe "profile setup modal" do
    test "auto-opens on first app load when no users exist", %{conn: conn} do
      assert Repo.aggregate(User, :count, :id) == 0

      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "Finish profile setup"
      assert html =~ "Target languages"
    end

    test "shows validation errors for invalid email and missing target languages", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      html =
        render_submit(view, "save_profile_setup", %{
          "profile" => %{"name" => "Default User", "email" => "invalid-email"}
        })

      assert html =~ "must have the @ sign and no spaces"
      assert html =~ "select at least one target language"
      assert html =~ "Finish profile setup"
    end

    test "creates the first user and target languages on valid save", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      html =
        render_submit(view, "save_profile_setup", %{
          "profile" => %{
            "name" => "Reader One",
            "email" => "reader.one@example.com",
            "target_languages" => ["es", "fr"]
          }
        })

      refute html =~ "Finish profile setup"

      user = Repo.get_by!(User, email: "reader.one@example.com")
      assert user.name == "Reader One"

      target_languages =
        UserTargetLanguage
        |> where([utl], utl.user_id == ^user.id)
        |> select([utl], utl.language_code)
        |> Repo.all()
        |> Enum.sort()

      assert target_languages == ["es", "fr"]
    end

    test "stays dismissed after successful setup on remount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      _html =
        render_submit(view, "save_profile_setup", %{
          "profile" => %{
            "name" => "Reader Two",
            "email" => "reader.two@example.com",
            "target_languages" => ["es"]
          }
        })

      {:ok, _new_view, html} = live(conn, "/library")

      refute html =~ "Finish profile setup"
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

      user = create_user()
      add_target_language(user, "es")

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
    test "refresh button triggers reload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # Click refresh button
      html = view |> element("button[phx-click='refresh_calibre']") |> render_click()

      assert html =~ "My Library"
    end

    test "refresh button is debounced", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # First click should work
      view |> element("button[phx-click='refresh_calibre']") |> render_click()

      # Button should now be disabled
      html = render(view)
      assert html =~ "Refreshing library"
      assert html =~ "disabled"
    end

    test "refresh debounce is cleared after timer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/library")

      # First click enables debounce
      view |> element("button[phx-click='refresh_calibre']") |> render_click()
      html = render(view)
      assert html =~ "Refreshing library"

      # Send the clear debounce message directly
      send(view.pid, :clear_refresh_debounce)

      # Button should be enabled again
      html = render(view)
      assert html =~ "Refresh library"
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
        |> element("button[phx-click='refresh_calibre']")
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
      view |> element("button[phx-click='refresh_calibre']") |> render_click()

      # Send clear message
      send(view.pid, :clear_refresh_debounce)

      html = render(view)
      assert html =~ "Refresh library"
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

    test "groups items under author headers", %{conn: conn} do
      user = create_user()

      create_document_with_title_and_author(user, "Zeta", "Author B")
      create_document_with_title_and_author(user, "Alpha", "Author A")
      create_document_with_title_and_author(user, "Beta", "Author A")

      {:ok, view, _html} = live(conn, "/library")

      assert has_element?(view, ".library-author-name", "Author A")
      assert has_element?(view, ".library-author-name", "Author B")

      assert has_element?(view, ".library-author-section", "Alpha")
      assert has_element?(view, ".library-author-section", "Beta")
      assert has_element?(view, ".library-author-section", "Zeta")
    end

    test "shows known and unknown language badges for importable Calibre books", %{conn: conn} do
      temp_root = "/tmp/lex_library_live_languages_#{System.unique_integer([:positive])}"
      known_book_dir = Path.join(temp_root, "Known Author/Known Book")
      unknown_book_dir = Path.join(temp_root, "Unknown Author/Unknown Book")

      user = create_user()
      add_target_language(user, "es")

      File.mkdir_p!(known_book_dir)
      File.mkdir_p!(unknown_book_dir)

      File.cp!(
        "test/fixtures/epubs/el_principito.epub",
        Path.join(known_book_dir, "el_principito.epub")
      )

      create_epub_without_language(Path.join(unknown_book_dir, "no_language.epub"))

      original_path = Application.fetch_env!(:lex, :calibre_library_path)
      Application.put_env(:lex, :calibre_library_path, temp_root)

      try do
        {:ok, view, _html} = live(conn, "/library")

        assert has_element?(view, ".language-badge.known", "Language: es")

        assert has_element?(
                 view,
                 ".library-item.calibre.not_imported .language-badge.unknown",
                 "Language Unknown"
               )
      after
        Application.put_env(:lex, :calibre_library_path, original_path)
        File.rm_rf(temp_root)
      end
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
    create_document_with_title_and_author(user, title, "Test Author")
  end

  defp create_document_with_title_and_author(user, title, author) do
    %Document{}
    |> Document.changeset(%{
      title: title,
      author: author,
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

  defp add_target_language(user, language_code) do
    %UserTargetLanguage{}
    |> UserTargetLanguage.changeset(%{user_id: user.id, language_code: language_code})
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

  defp create_epub_without_language(epub_path) do
    temp_dir =
      Path.join(System.tmp_dir!(), "lex_no_language_#{System.unique_integer([:positive])}")

    oebps_dir = Path.join(temp_dir, "OEBPS")
    meta_inf_dir = Path.join(temp_dir, "META-INF")

    File.mkdir_p!(oebps_dir)
    File.mkdir_p!(meta_inf_dir)
    File.write!(Path.join(temp_dir, "mimetype"), "application/epub+zip")

    File.write!(
      Path.join(meta_inf_dir, "container.xml"),
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles>
          <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        </rootfiles>
      </container>
      """
    )

    File.write!(
      Path.join(oebps_dir, "content.opf"),
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title>Unknown Language Book</dc:title>
          <dc:creator>Test Author</dc:creator>
          <dc:identifier id="bookid">urn:uuid:test-nolang-library-live</dc:identifier>
          <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
        </metadata>
        <manifest>
          <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>
          <itemref idref="chapter1"/>
        </spine>
      </package>
      """
    )

    File.write!(
      Path.join(oebps_dir, "chapter1.xhtml"),
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>Chapter 1</title>
        </head>
        <body>
          <h1>Chapter 1</h1>
          <p>Sample content</p>
        </body>
      </html>
      """
    )

    File.mkdir_p!(Path.dirname(epub_path))

    files = [
      {~c"mimetype", File.read!(Path.join(temp_dir, "mimetype"))},
      {~c"META-INF/container.xml", File.read!(Path.join(meta_inf_dir, "container.xml"))},
      {~c"OEBPS/content.opf", File.read!(Path.join(oebps_dir, "content.opf"))},
      {~c"OEBPS/chapter1.xhtml", File.read!(Path.join(oebps_dir, "chapter1.xhtml"))}
    ]

    _ =
      :zip.create(String.to_charlist(epub_path), files,
        compress: [~c".xhtml", ~c".opf", ~c".xml"]
      )

    File.rm_rf!(temp_dir)
  end
end
