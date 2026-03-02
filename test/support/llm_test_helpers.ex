defmodule Lex.LLMTestHelpers do
  @moduledoc """
  Test helpers for LLM help functionality.

  Provides convenience functions for:
  - Creating test documents with sentences and tokens
  - Setting up mock LLM responses
  - Asserting popup state in LiveView tests
  """

  import ExUnit.Assertions
  import Phoenix.LiveViewTest

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Lexeme
  alias Lex.Text.Sentence
  alias Lex.Text.Token

  @doc """
  Creates a test user with the specified primary language.

  ## Examples

      user = create_user("en")
      user = create_user("es", email: "custom@example.com")
  """
  def create_user(primary_language \\ "en", attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Test User",
      email: "test#{unique_id}_#{:erlang.monotonic_time()}@example.com",
      primary_language: primary_language
    }

    attrs = Map.merge(default_attrs, attrs)

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a ready document with the specified language.

  ## Examples

      document = create_ready_document(user, "es")
  """
  def create_ready_document(user, language \\ "en", attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      title: "Test Document #{unique_id}",
      author: "Test Author",
      language: language,
      status: "ready",
      source_file: "test.epub",
      user_id: user.id
    }

    attrs = Map.merge(default_attrs, attrs)

    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a section in a document.

  ## Examples

      section = create_section(document, "Chapter 1")
  """
  def create_section(document, title \\ "Test Section", position \\ 1) do
    %Section{}
    |> Section.changeset(%{
      document_id: document.id,
      position: position,
      title: title
    })
    |> Repo.insert!()
  end

  @doc """
  Creates a sentence in a section.

  ## Examples

      sentence = create_sentence(section, 1, "Hello world.")
  """
  def create_sentence(section, position \\ 1, text \\ "Test sentence.") do
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

  @doc """
  Creates tokens for a sentence from a list of words.

  ## Examples

      tokens = create_tokens_for_sentence(sentence, ["Hello", "world", "."])
  """
  def create_tokens_for_sentence(sentence, words) when is_list(words) do
    words
    |> Enum.with_index(1)
    |> Enum.map(fn {word, position} ->
      lexeme_id =
        if word in [".", ",", "!", "?", ";", ":"] do
          nil
        else
          lexeme = create_lexeme(%{lemma: String.downcase(word)})
          lexeme.id
        end

      %Token{}
      |> Token.changeset(%{
        sentence_id: sentence.id,
        position: position,
        surface: word,
        normalized_surface: String.downcase(word),
        lemma: String.downcase(word),
        pos: "WORD",
        is_punctuation: word in [".", ",", "!", "?", ";", ":"],
        char_start: 0,
        char_end: String.length(word),
        lexeme_id: lexeme_id
      })
      |> Repo.insert!()
    end)
  end

  @doc """
  Creates a lexeme with default attributes.

  ## Examples

      lexeme = create_lexeme(%{lemma: "hola", language: "es"})
  """
  def create_lexeme(attrs) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      language: "en",
      lemma: "test#{unique_id}",
      normalized_lemma: "test#{unique_id}",
      pos: "NOUN"
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lexeme{}
    |> Lexeme.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a cached LLM help response in the database.

  ## Examples

      request = create_cached_llm_response(user, document, sentence, token, "This means hello.")
  """
  def create_cached_llm_response(user, document, sentence, token, response_text, language \\ "en") do
    %Lex.Vocab.LlmHelpRequest{}
    |> Lex.Vocab.LlmHelpRequest.changeset(%{
      user_id: user.id,
      document_id: document.id,
      sentence_id: sentence.id,
      token_id: token.id,
      request_type: "token",
      response_language: language,
      provider: "openai",
      model: "gpt-4",
      response_text: response_text
    })
    |> Repo.insert!()
  end

  @doc """
  Sets up a mock LLM response that will be returned by the mock client.

  ## Examples

      set_mock_llm_response("Hello, this is the help text.")
  """
  def set_mock_llm_response(response_text) do
    Lex.LLM.ClientMock.set_mock_response(response_text)
  end

  @doc """
  Sets up mock LLM chunks that will be streamed by the mock client.

  ## Examples

      set_mock_llm_chunks(["Hello, ", "how ", "are ", "you?"])
  """
  def set_mock_llm_chunks(chunks) when is_list(chunks) do
    Lex.LLM.ClientMock.set_mock_chunks(chunks)
  end

  @doc """
  Sets up a mock LLM error.

  ## Examples

      set_mock_llm_error(:timeout)
      set_mock_llm_error({:http_error, 500})
  """
  def set_mock_llm_error(reason) do
    Lex.LLM.ClientMock.set_mock_error(reason)
  end

  @doc """
  Clears all mock LLM state.

  ## Examples

      clear_mock_llm()
  """
  def clear_mock_llm do
    Lex.LLM.ClientMock.clear_mock()
  end

  @doc """
  Asserts that the LLM popup is visible in the LiveView.

  ## Examples

      assert_popup_visible(view)
  """
  def assert_popup_visible(view) do
    assert has_element?(view, "[data-testid=\"llm-popup\"]")
  end

  @doc """
  Asserts that the LLM popup is hidden in the LiveView.

  ## Examples

      assert_popup_hidden(view)
  """
  def assert_popup_hidden(view) do
    refute has_element?(view, "[data-testid=\"llm-popup\"]")
  end

  @doc """
  Asserts that the loading state is visible in the popup.

  ## Examples

      assert_loading_visible(view)
  """
  def assert_loading_visible(view) do
    html = render(view)
    assert html =~ "Thinking..."
  end

  @doc """
  Asserts that the loading state is not visible in the popup.

  ## Examples

      assert_loading_hidden(view)
  """
  def assert_loading_hidden(view) do
    html = render(view)
    refute html =~ "Thinking..."
  end

  @doc """
  Asserts that the specified content is displayed in the popup.

  ## Examples

      assert_popup_content(view, "This means hello.")
  """
  def assert_popup_content(view, content) do
    popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
    assert popup_html =~ content
  end

  @doc """
  Asserts that an error message is displayed in the popup.

  ## Examples

      assert_popup_error(view, "An error occurred")
  """
  def assert_popup_error(view, message \\ nil) do
    popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()

    if message do
      assert popup_html =~ message
    else
      assert popup_html =~ "llm-popup-error"
    end
  end

  @doc """
  Focuses a token by its index using keyboard navigation.

  ## Examples

      focus_token(view, 3)
  """
  def focus_token(view, token_index) do
    # Navigate to the token (assuming we start at index 0)
    for _ <- 1..token_index do
      render_hook(view, "key_nav", %{"key" => "w"})
    end

    view
  end

  @doc """
  Opens the LLM help popup by pressing space.

  ## Examples

      open_llm_popup(view)
  """
  def open_llm_popup(view) do
    render_hook(view, "key_nav", %{"key" => "space"})
    view
  end

  @doc """
  Closes the LLM help popup by pressing space.

  ## Examples

      close_llm_popup(view)
  """
  def close_llm_popup(view) do
    render_hook(view, "key_nav", %{"key" => "space"})
    view
  end
end
