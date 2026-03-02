# Debug script to see what events are logged
code = """
defmodule DebugTest do
  use Lex.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Text.Token
  alias Lex.Text.Lexeme
  alias Lex.Vocab.UserLexemeState
  alias Lex.Reader.ReadingEvent

  test "debug known words", %{conn: conn} do
    user = create_user()
    document = create_ready_document(user)
    section = create_section(document)
    sentence = create_sentence(section, 1, "Hola.")
    lexeme = create_lexeme(%{lemma: "hola", normalized_lemma: "hola"})
    create_token(sentence.id, lexeme.id, %{position: 1, surface: "Hola"})

    # Create known state
    {:ok, _} =
      %UserLexemeState{}
      |> UserLexemeState.changeset(%{
        user_id: user.id,
        lexeme_id: lexeme.id,
        status: "known",
        seen_count: 10,
        known_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    # Mount
    {:ok, view, _html} = live(conn, "/read/#{document.id}")

    IO.inspect(Repo.all(ReadingEvent), label: "Events after mount")

    # Focus and try to toggle
    render_hook(view, :key_nav, %{"key" => "w"})
    render_hook(view, :key_nav, %{"key" => "l"})

    IO.inspect(Repo.all(ReadingEvent), label: "Events after toggle")

    # Check all events
    events = Repo.all(ReadingEvent)
    IO.inspect(Enum.map(events, & &1.event_type), label: "All event types")
  end

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

  defp create_section(document, title \\\\ "Test Section") do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: 1,
      title: title
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

  defp create_lexeme(attrs) do
    unique_id = System.unique_integer([:positive])
    default_attrs = %{
      language: "es",
      lemma: "test#{unique_id}",
      normalized_lemma: "test#{unique_id}",
      pos: "NOUN"
    }
    attrs = Map.merge(default_attrs, attrs)
    %Lexeme{}
    |> Lexeme.changeset(attrs)
    |> Repo.insert!()
  end

  defp create_token(sentence_id, lexeme_id, attrs) do
    unique_id = System.unique_integer([:positive])
    default_attrs = %{
      position: 1,
      surface: "test",
      normalized_surface: "test",
      lemma: "test#{unique_id}",
      pos: "NOUN",
      is_punctuation: false,
      char_start: 0,
      char_end: 4,
      sentence_id: sentence_id,
      lexeme_id: lexeme_id
    }
    attrs = Map.merge(default_attrs, attrs)
    %Token{}
    |> Token.changeset(attrs)
    |> Repo.insert!()
  end
end
"""

File.write!("test/lex_web/live/reader_live/debug_test.exs", code)
IO.puts("Debug test written")
