defmodule LexWeb.ReaderLive.ShowTest do
  use Lex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lex.Repo
  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Lexeme
  alias Lex.Text.Sentence
  alias Lex.Text.Token
  alias Lex.Vocab

  setup do
    # Clear mock state before each test
    Lex.LLM.ClientMock.clear_mock()
    :ok
  end

  describe "show" do
    test "mounts with valid document and position", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "This"
      assert html =~ "is"
      assert html =~ "test"
      assert html =~ section.title
    end

    test "redirects to library for invalid document_id", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/library"}}} = live(conn, "/read/999999")
    end

    test "shows correct section and sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document, "Chapter 1: The Beginning")
      sentence = create_sentence(section, 1, "It was the best of times.")
      create_tokens_for_sentence(sentence, ["It", "was", "the", "best", "of", "times", "."])

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "Chapter 1: The Beginning"
      assert html =~ "It"
      assert html =~ "was"
      assert html =~ "best"
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
      sentence = create_sentence(section, 1, "A sentence in an untitled section.")

      create_tokens_for_sentence(sentence, [
        "A",
        "sentence",
        "in",
        "an",
        "untitled",
        "section",
        "."
      ])

      {:ok, _view, html} = live(conn, "/read/#{document.id}")

      assert html =~ "Untitled Section"
      assert html =~ "sentence"
      assert html =~ "untitled"
    end

    test "j navigation advances by one sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)

      sentence_1 = create_sentence(section, 1, "First sentence.")
      sentence_2 = create_sentence(section, 2, "Second sentence.")
      sentence_3 = create_sentence(section, 3, "Third sentence.")

      create_tokens_for_sentence(sentence_1, ["First", "sentence", "."])
      create_tokens_for_sentence(sentence_2, ["Second", "sentence", "."])
      create_tokens_for_sentence(sentence_3, ["Third", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "First"
      refute current_sentence_html =~ "Second"

      _html = render_hook(view, "key_nav", %{"key" => "j"})
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "Second"
      refute current_sentence_html =~ "Third"
    end
  end

  describe "llm_help" do
    test "pressing space with focused token shows popup and streams response", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      _tokens = create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock to return chunks
      chunks = ["This ", "is ", "the ", "help ", "response."]
      Lex.LLM.ClientMock.set_mock_chunks(chunks)
      Lex.LLM.ClientMock.set_chunk_delay(0)

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus the token (index 4 for "test")
      for _ <- 1..4 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      # Press space to request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Wait for streaming to complete (chunks are processed asynchronously)
      Process.sleep(500)

      # Verify final response is displayed
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "This is the help response."

      # Verify loading state is gone
      refute popup_html =~ "Thinking..."

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "pressing space again hides popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token and show popup
      _html = render_hook(view, "key_nav", %{"key" => "w"})
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Press space again to hide popup
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is hidden
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "clicking popup close button hides popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token and show popup
      _html = render_hook(view, "key_nav", %{"key" => "w"})
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Click the close button to hide popup
      view |> element(".llm-popup-close") |> render_click()

      # Verify popup is hidden
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "dismiss_llm_popup event resets popup state", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token and show popup
      _html = render_hook(view, "key_nav", %{"key" => "w"})
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Wait for response
      Process.sleep(200)

      # Verify popup is visible with content
      assert view |> has_element?("[data-testid=\"llm-popup\"]")
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "Help text"

      # Dismiss via direct event (simulating JS hook)
      _html = render_click(view, :dismiss_llm_popup)

      # Verify popup is hidden
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "cached response returned immediately without LLM call", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      tokens = create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])
      token = Enum.find(tokens, &(&1.surface == "test"))

      # Pre-create a cached response
      {:ok, _} =
        Vocab.log_llm_request(user.id, document.id, sentence.id, token.id, :token)

      # Update it with a response
      {:ok, _request} =
        Repo.get_by(Lex.Vocab.LlmHelpRequest,
          user_id: user.id,
          document_id: document.id,
          sentence_id: sentence.id,
          token_id: token.id
        )
        |> Ecto.Changeset.change(response_text: "Cached help response")
        |> Repo.update()

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus the token
      for _ <- 1..4 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      # Press space to request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Should show popup immediately
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Should show cached response immediately (no loading state)
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "Cached help response"
      refute popup_html =~ "Thinking..."
      assert Lex.LLM.ClientMock.get_last_request() == nil
      assert Lex.LLM.ClientMock.get_last_options() == []
    end

    test "LLM error shows error message", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock to return an error
      Lex.LLM.ClientMock.set_mock_error(:timeout)

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token
      for _ <- 1..4 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      # Press space to request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Should show popup
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Wait for error to be processed
      Process.sleep(300)

      # Wait for error to be processed
      Process.sleep(500)

      # Should show error message (using the class name)
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "class=\"llm-popup-error\""

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "streaming chunks appear progressively in popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hello world.")
      _tokens = create_tokens_for_sentence(sentence, ["Hello", "world", "."])

      # Set up chunks that will arrive one at a time
      chunks = ["First ", "chunk ", "appears.", " Then ", "second."]
      Lex.LLM.ClientMock.set_mock_chunks(chunks)
      Lex.LLM.ClientMock.set_chunk_delay(0)

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Wait for streaming to complete
      Process.sleep(500)

      # Verify all chunks are displayed
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "First chunk appears. Then second."

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "final response is displayed after streaming completes", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hello world.")
      _tokens = create_tokens_for_sentence(sentence, ["Hello", "world", "."])

      # Set up a complete response
      Lex.LLM.ClientMock.set_mock_response("This is the complete help response for testing.")
      Lex.LLM.ClientMock.set_chunk_delay(0)

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Wait for streaming to complete
      Process.sleep(500)

      # Wait a bit more for the final update
      Process.sleep(200)

      # Verify final response is displayed
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "This is the complete help response for testing."

      # Verify loading is complete
      refute popup_html =~ "Thinking..."

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "loading state is shown while waiting for LLM response", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hello world.")
      _tokens = create_tokens_for_sentence(sentence, ["Hello", "world", "."])

      # Set up slow response to keep loading state visible
      Lex.LLM.ClientMock.set_mock_response("Response")
      Lex.LLM.ClientMock.set_chunk_delay(500)

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Immediately check for loading state (before streaming completes)
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "Thinking..."

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "sentence-level help shows popup with placeholder", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test sentence.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Don't focus any token - request sentence-level help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Verify sentence-level help placeholder is shown
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "Sentence-level help coming soon"
      assert Lex.LLM.ClientMock.get_last_request() == nil
      assert Lex.LLM.ClientMock.get_last_options() == []
    end

    test "HTTP 4xx error displays appropriate message", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hello world.")
      create_tokens_for_sentence(sentence, ["Hello", "world", "."])

      # Set up 4xx error
      Lex.LLM.ClientMock.set_mock_error({:http_error, 400})

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      Process.sleep(500)

      # Verify error is displayed
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "class=\"llm-popup-error\""

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "HTTP 5xx error displays appropriate message", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Hello world.")
      create_tokens_for_sentence(sentence, ["Hello", "world", "."])

      # Set up 5xx error
      Lex.LLM.ClientMock.set_mock_error({:http_error, 500})

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Request help
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      Process.sleep(500)

      # Verify error is displayed
      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "class=\"llm-popup-error\""

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "j key dismisses open LLM popup and navigates to next sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence_1 = create_sentence(section, 1, "First sentence here.")
      sentence_2 = create_sentence(section, 2, "Second sentence here.")
      create_tokens_for_sentence(sentence_1, ["First", "sentence", "here", "."])
      create_tokens_for_sentence(sentence_2, ["Second", "sentence", "here", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Verify first sentence is displayed
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "First"
      refute current_sentence_html =~ "Second"

      # Focus a token and show popup
      _html = render_hook(view, "key_nav", %{"key" => "w"})
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Press j to navigate next (should dismiss popup and navigate)
      _html = render_hook(view, "key_nav", %{"key" => "j"})

      # Verify popup is dismissed
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Verify navigated to second sentence
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "Second"
      refute current_sentence_html =~ "First"

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "k key dismisses open LLM popup and navigates to previous sentence", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence_1 = create_sentence(section, 1, "First sentence here.")
      sentence_2 = create_sentence(section, 2, "Second sentence here.")
      create_tokens_for_sentence(sentence_1, ["First", "sentence", "here", "."])
      create_tokens_for_sentence(sentence_2, ["Second", "sentence", "here", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Navigate to second sentence first
      _html = render_hook(view, "key_nav", %{"key" => "j"})

      # Verify second sentence is displayed
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "Second"
      refute current_sentence_html =~ "First"

      # Focus a token and show popup
      _html = render_hook(view, "key_nav", %{"key" => "w"})
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Press k to navigate previous (should dismiss popup and navigate)
      _html = render_hook(view, "key_nav", %{"key" => "k"})

      # Verify popup is dismissed
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Verify navigated back to first sentence
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "First"
      refute current_sentence_html =~ "Second"

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "w key dismisses open LLM popup and focuses next token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus first token
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Show popup
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Press w to focus next token (should dismiss popup)
      _html = render_hook(view, "key_nav", %{"key" => "w"})

      # Verify popup is dismissed
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "b key dismisses open LLM popup and focuses previous token", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "First second third.")
      create_tokens_for_sentence(sentence, ["First", "second", "third", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus third token (w three times)
      for _ <- 1..3 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      # Show popup
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible
      assert view |> has_element?("[data-testid=\"llm-popup\"]")

      # Press b to focus previous token (should dismiss popup)
      _html = render_hook(view, "key_nav", %{"key" => "b"})

      # Verify popup is dismissed
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "navigation works normally when popup is not open", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence_1 = create_sentence(section, 1, "First sentence here.")
      sentence_2 = create_sentence(section, 2, "Second sentence here.")
      create_tokens_for_sentence(sentence_1, ["First", "sentence", "here", "."])
      create_tokens_for_sentence(sentence_2, ["Second", "sentence", "here", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Verify first sentence is displayed (popup is NOT open)
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "First"
      refute current_sentence_html =~ "Second"

      refute view |> has_element?("[data-testid='llm-popup']")

      # Press j without opening popup
      _html = render_hook(view, "key_nav", %{"key" => "j"})

      # Verify navigated successfully
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "Second"
      refute current_sentence_html =~ "First"

      # Still no popup
      refute view |> has_element?("[data-testid='llm-popup']")
    end
  end

  describe "space key toggle behavior" do
    test "space when popup closed sets word to learning and opens popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus the token "test" (index 4 - need to navigate to it)
      for _ <- 1..4 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      # Verify popup is not visible initially
      refute view |> has_element?("[data-testid='llm-popup']")

      # Get token class before space press
      current_sentence_html = view |> element(".current-sentence") |> render()
      # Token starts with default status styling
      assert current_sentence_html =~ "token-default"

      # Press space to set learning and open popup
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is now visible
      assert view |> has_element?("[data-testid='llm-popup']")

      # Verify word is now learning - check for token-learning class
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "token-learning"

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "space when popup open sets word to known and closes popup", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus a token and open popup (which also sets to learning)
      for _ <- 1..4 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is visible and word is learning
      assert view |> has_element?("[data-testid='llm-popup']")
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "token-learning"

      # Press space again to set known and close popup
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Verify popup is closed
      refute view |> has_element?("[data-testid='llm-popup']")

      # Verify word is now known - check that learning class is gone
      # Known words don't have a special class, they use default styling
      current_sentence_html = view |> element(".current-sentence") |> render()
      refute current_sentence_html =~ "token-learning"

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "space cycles word through learning and known states correctly", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      # Set up mock response
      Lex.LLM.ClientMock.set_mock_response("Help text")

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Focus token "test"
      for _ <- 1..4 do
        _html = render_hook(view, "key_nav", %{"key" => "w"})
      end

      # Initial state: verify popup is closed
      refute view |> has_element?("[data-testid='llm-popup']")

      # After first space: learning + popup open
      _html = render_hook(view, "key_nav", %{"key" => "space"})
      assert view |> has_element?("[data-testid='llm-popup']")
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "token-learning"

      # After second space: known + popup closed
      _html = render_hook(view, "key_nav", %{"key" => "space"})
      refute view |> has_element?("[data-testid='llm-popup']")
      current_sentence_html = view |> element(".current-sentence") |> render()
      # Known words use default styling (no special class)
      refute current_sentence_html =~ "token-learning"

      # After third space: learning again + popup open
      _html = render_hook(view, "key_nav", %{"key" => "space"})
      assert view |> has_element?("[data-testid='llm-popup']")
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "token-learning"

      # Clean up
      Lex.LLM.ClientMock.clear_mock()
    end

    test "space without focused token handles gracefully", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "This is a test.")
      create_tokens_for_sentence(sentence, ["This", "is", "a", "test", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      # Don't focus any token (focused_token_index should be 0)
      # Verify initial state
      refute view |> has_element?("[data-testid='llm-popup']")

      # Press space without focused token
      _html = render_hook(view, "key_nav", %{"key" => "space"})

      # Should not crash - view is still functional
      # Verify view is still working by checking sentence is still displayed
      current_sentence_html = view |> element(".current-sentence") |> render()
      assert current_sentence_html =~ "This"
      assert current_sentence_html =~ "test"

      # Popup should show sentence-level help placeholder (no focused token)
      assert view |> has_element?("[data-testid='llm-popup']")
      popup_html = view |> element("[data-testid='llm-popup']") |> render()
      assert popup_html =~ "Sentence-level help coming soon"
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

  defp create_tokens_for_sentence(sentence, words) do
    words
    |> Enum.with_index(1)
    |> Enum.map(fn {word, position} ->
      # Create a lexeme for non-punctuation words
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

  defp create_lexeme(attrs) do
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
end
