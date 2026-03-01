defmodule LexWeb.ReaderLive.ShowTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence

  describe "show" do
    test "mounts with valid document and position", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      _sentence = create_sentence(section, 1, "This is a test sentence.")

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "This is a test sentence."
      assert html =~ section.title
    end

    test "redirects to library for invalid document_id", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/library"}}} = live(conn, "/read/999999")
    end

    test "shows correct section and sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document, "Chapter 1: The Beginning")
      _sentence = create_sentence(section, 1, "It was the best of times.")

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "Chapter 1: The Beginning"
      assert html =~ "It was the best of times."
    end

    test "shows empty state when document has no sentences", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      _section = create_section(document)

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "No content available for this document."
    end

    test "shows untitled section when section has no title", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section_without_title(document)
      _sentence = create_sentence(section, 1, "A sentence in an untitled section.")

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "Untitled Section"
      assert html =~ "A sentence in an untitled section."
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
    %Document{}
    |> Document.changeset(%{
      title: "Test Document",
      author: "Test Author",
      language: "en",
      status: "ready",
      source_file: "test.epub",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp create_section(document, title \\ "Test Section") do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: 1,
      title: title
    })
    |> Repo.insert!()
  end

  defp create_section_without_title(document) do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: 1,
      title: nil
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
end
