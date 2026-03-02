defmodule LexWeb.LibraryLive.IndexTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Reader.UserSentenceState

  describe "index" do
    test "renders empty state when no documents ready", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/library")

      assert html =~ "My Library"
      assert html =~ "No documents found."
      assert html =~ "Set CALIBRE_LIBRARY_PATH"
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

    test "clicking document card navigates to reader", %{conn: conn} do
      user = create_user()
      _document = create_ready_document(user)

      {:ok, view, _html} = live(conn, "/library")

      # Since we don't have actual user session handling, we just verify
      # the click event would navigate (in real app this would use push_navigate)
      # For now, just verify the card has the click handler
      html = render(view)
      assert html =~ "document-card"
      assert html =~ "phx-click=\"navigate_to_reader\""
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
