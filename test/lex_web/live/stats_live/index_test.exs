defmodule LexWeb.StatsLive.IndexTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Reader.UserSentenceState
  alias Lex.Repo
  alias Lex.Text.Lexeme
  alias Lex.Text.Sentence
  alias Lex.Vocab.UserLexemeState

  describe "stats dashboard" do
    test "renders chart when timeline has a single day", %{conn: conn} do
      user = create_user()

      create_lexeme_state(user, "seen", ~U[2026-01-02 12:00:00Z], nil, nil)

      {:ok, _view, html} = live(conn, "/stats")

      assert html =~ "Cumulative Vocabulary Timeline"
      assert html =~ "Vocabulary growth chart"
      assert html =~ "Words Read"
      assert html =~ ">1<"
    end

    test "renders vocabulary counts, chart, and book progress", %{conn: conn} do
      user = create_user()

      create_lexeme_state(user, "seen", ~U[2026-01-02 12:00:00Z], nil, nil)

      create_lexeme_state(
        user,
        "learning",
        ~U[2026-01-03 12:00:00Z],
        ~U[2026-01-04 12:00:00Z],
        nil
      )

      create_lexeme_state(
        user,
        "known",
        ~U[2026-01-05 12:00:00Z],
        ~U[2026-01-06 12:00:00Z],
        ~U[2026-01-07 12:00:00Z]
      )

      in_progress_doc = create_document(user, "In Progress Book")
      in_progress_section = create_section(in_progress_doc)

      in_progress_sentences =
        for position <- 1..4 do
          create_sentence(in_progress_section, position)
        end

      mark_sentence_read(user, Enum.at(in_progress_sentences, 0))
      mark_sentence_read(user, Enum.at(in_progress_sentences, 1))

      completed_doc = create_document(user, "Completed Book")
      completed_section = create_section(completed_doc)

      completed_sentences =
        for position <- 1..3 do
          create_sentence(completed_section, position)
        end

      Enum.each(completed_sentences, &mark_sentence_read(user, &1))

      {:ok, _view, html} = live(conn, "/stats")

      assert html =~ "Stats"
      assert html =~ "Library"
      assert html =~ "Words Read"
      assert html =~ "Words Learning"
      assert html =~ "Words Known"
      assert html =~ ">3<"
      assert html =~ ">1<"
      assert html =~ "Cumulative Vocabulary Timeline"
      assert html =~ "Vocabulary growth chart"

      assert html =~ "In Progress"
      assert html =~ "In Progress Book"
      assert html =~ "2/4 sentences"

      assert html =~ "Completed"
      assert html =~ "Completed Book"
      assert html =~ "3 sentences read"
    end

    test "renders empty states when user has no activity", %{conn: conn} do
      _user = create_user()

      {:ok, _view, html} = live(conn, "/stats")

      assert html =~ "No reading activity yet."
      assert html =~ "No books in progress."
      assert html =~ "No books completed yet."
      assert html =~ ">0<"
    end
  end

  defp create_user do
    %User{}
    |> User.changeset(%{
      name: "Stats User",
      email: "stats#{System.unique_integer()}_#{:erlang.monotonic_time()}@example.com",
      primary_language: "en"
    })
    |> Repo.insert!()
  end

  defp create_lexeme_state(user, status, first_seen_at, learning_since, known_at) do
    lexeme = create_lexeme()

    %UserLexemeState{}
    |> UserLexemeState.changeset(%{
      user_id: user.id,
      lexeme_id: lexeme.id,
      status: status,
      seen_count: 1,
      first_seen_at: first_seen_at,
      learning_since: learning_since,
      known_at: known_at,
      last_seen_at: first_seen_at
    })
    |> Repo.insert!()
  end

  defp create_lexeme do
    unique_id = System.unique_integer([:positive])

    %Lexeme{}
    |> Lexeme.changeset(%{
      language: "en",
      lemma: "lemma_#{unique_id}",
      normalized_lemma: "lemma_#{unique_id}",
      pos: "NOUN"
    })
    |> Repo.insert!()
  end

  defp create_document(user, title) do
    %Document{}
    |> Document.changeset(%{
      title: title,
      author: "Test Author",
      language: "en",
      status: "ready",
      source_file: "#{title}.epub",
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp create_section(document) do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: 1,
      title: "Section 1"
    })
    |> Repo.insert!()
  end

  defp create_sentence(section, position) do
    text = "Sentence #{position}"

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
