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
  alias Lex.Text.Token
  alias Lex.Vocab.UserLexemeState

  describe "stats dashboard" do
    test "renders chart when timeline has a single day", %{conn: conn} do
      user = create_user()

      create_lexeme_state(user, "seen", ~U[2026-01-02 12:00:00Z], nil, nil)

      {:ok, view, _html} = live(conn, "/stats")

      assert has_element?(view, ".stats-chart")
      assert has_element?(view, ".stats-chart .series.words-read")
      assert has_element?(view, ".stats-chart .series.known")
      assert has_element?(view, ".stats-chart .series.learning")

      chart_labels = grid_label_values(render(view))
      assert Enum.max(chart_labels) == 1
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

      create_sentence_tokens(Enum.at(in_progress_sentences, 0), ["alpha", "beta", "."])
      create_sentence_tokens(Enum.at(in_progress_sentences, 1), ["gamma", "delta", "!"])

      completed_doc = create_document(user, "Completed Book")
      completed_section = create_section(completed_doc)

      completed_sentences =
        for position <- 1..3 do
          create_sentence(completed_section, position)
        end

      Enum.each(completed_sentences, &mark_sentence_read(user, &1))

      create_sentence_tokens(Enum.at(completed_sentences, 0), ["one", "two", ","])
      create_sentence_tokens(Enum.at(completed_sentences, 1), ["three", "four", "."])
      create_sentence_tokens(Enum.at(completed_sentences, 2), ["five", "six", "?"])

      {:ok, view, _html} = live(conn, "/stats")

      assert stats_card_values(render(view)) == [10, 2, 1, 1]

      assert has_element?(view, ".book-progress-row .book-title", "In Progress Book")
      assert has_element?(view, ".book-progress-row .book-meta", "2/4 sentences")

      assert has_element?(view, ".book-completed-row .book-title", "Completed Book")
      assert has_element?(view, ".book-completed-row .book-meta", "3 sentences read")

      refute has_element?(view, ".book-progress-row .book-title", "Completed Book")
      refute has_element?(view, ".book-completed-row .book-title", "In Progress Book")
    end

    test "renders empty states when user has no activity", %{conn: conn} do
      _user = create_user()

      {:ok, view, _html} = live(conn, "/stats")

      refute has_element?(view, ".stats-chart")
      refute has_element?(view, ".book-progress-row")
      refute has_element?(view, ".book-completed-row")
      assert stats_card_values(render(view)) == [0, 0, 0, 0]
    end

    test "toggles chart series from legend and rescales y axis", %{conn: conn} do
      user = create_user()

      create_lexeme_state(user, "known", ~U[2026-01-05 12:00:00Z], nil, ~U[2026-01-06 12:00:00Z])

      doc = create_document(user, "Words Heavy")
      section = create_section(doc)
      sentence = create_sentence(section, 1)

      mark_sentence_read(user, sentence)

      create_sentence_tokens(
        sentence,
        Enum.map(1..30, fn idx -> "word#{idx}" end)
      )

      {:ok, view, _html} = live(conn, "/stats")

      assert Enum.max(grid_label_values(render(view))) == 30
      assert has_element?(view, ".stats-chart .series.words-read")
      refute has_element?(view, ".stats-legend .legend-toggle[phx-value-series='learning']")
      refute has_element?(view, ".stats-legend .legend-toggle[phx-value-series='known']")

      view
      |> element(".stats-legend .legend-toggle[phx-value-series='words-read']")
      |> render_click()

      refute has_element?(view, ".stats-chart .series.words-read")
      assert Enum.max(grid_label_values(render(view))) == 1

      assert has_element?(
               view,
               ".stats-legend .legend-toggle.is-hidden[phx-value-series='words-read']"
             )
    end

    test "limits x-axis labels to six evenly spaced dates", %{conn: conn} do
      user = create_user()

      for day <- 2..11 do
        create_lexeme_state(
          user,
          "seen",
          ~U[2026-01-01 12:00:00Z] |> DateTime.add((day - 1) * 86_400),
          nil,
          nil
        )
      end

      {:ok, view, _html} = live(conn, "/stats")

      labels = axis_labels(render(view))

      assert length(labels) <= 6
      assert hd(labels) == "02/01"
      assert List.last(labels) == "11/01"
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

  defp create_sentence_tokens(sentence, surfaces) do
    Enum.with_index(surfaces, 1)
    |> Enum.each(fn {surface, position} ->
      punctuation? = String.match?(surface, ~r/^[[:punct:]]+$/)

      %Token{}
      |> Token.changeset(%{
        sentence_id: sentence.id,
        position: position,
        surface: surface,
        normalized_surface: String.downcase(surface),
        lemma: String.downcase(surface),
        pos: if(punctuation?, do: "PUNCT", else: "NOUN"),
        is_punctuation: punctuation?
      })
      |> Repo.insert!()
    end)
  end

  defp stats_card_values(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".stats-cards .stats-value")
    |> Enum.map(fn card ->
      card
      |> Floki.text()
      |> String.trim()
      |> String.to_integer()
    end)
  end

  defp grid_label_values(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".stats-chart .grid-label")
    |> Enum.map(fn label ->
      label
      |> Floki.text()
      |> String.trim()
      |> String.to_integer()
    end)
  end

  defp axis_labels(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".stats-chart .axis-label")
    |> Enum.map(fn label ->
      label
      |> Floki.text()
      |> String.trim()
    end)
  end
end
