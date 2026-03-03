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
  alias Lex.TestLLMStreamingPlug

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

    test "creates one LLM connection owner per LiveView session", %{conn: conn} do
      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Session owner test sentence.")
      create_tokens_for_sentence(sentence, ["Session", "owner", "test", "sentence", "."])

      {:ok, view1, _html} = live(conn, "/read/#{document.id}")
      owner1 = llm_connection_owner(view1)

      assert is_pid(owner1)
      assert Process.alive?(owner1)

      {:ok, view2, _html} = live(conn, "/read/#{document.id}")
      owner2 = llm_connection_owner(view2)

      assert is_pid(owner2)
      assert Process.alive?(owner2)
      refute owner1 == owner2
    end

    test "LLM connection owner terminates when LiveView session ends", %{conn: conn} do
      previous_trap_exit = Process.flag(:trap_exit, true)
      on_exit(fn -> Process.flag(:trap_exit, previous_trap_exit) end)

      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Owner cleanup test sentence.")
      create_tokens_for_sentence(sentence, ["Owner", "cleanup", "test", "sentence", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")
      owner = llm_connection_owner(view)

      owner_ref = Process.monitor(owner)

      Process.exit(view.pid, :shutdown)

      assert_receive {:DOWN, ^owner_ref, :process, ^owner, _reason}, 1000
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

    test "repeated token help requests in one session reuse the same owner path", %{conn: conn} do
      original_client = Application.get_env(:lex, :llm_client)
      original_api_key = Application.get_env(:lex, :llm_api_key)
      original_base_url = Application.get_env(:lex, :llm_base_url)
      original_timeout = Application.get_env(:lex, :llm_timeout_ms)

      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_api_key, "test_api_key")
      TestLLMStreamingPlug.ensure_counter!()
      TestLLMStreamingPlug.set_mode(:normal)

      port = random_available_port()

      start_supervised!(
        {Plug.Cowboy,
         scheme: :http,
         plug: TestLLMStreamingPlug,
         options: [port: port, protocol_options: [idle_timeout: 30_000]]}
      )

      Application.put_env(:lex, :llm_base_url, "http://127.0.0.1:#{port}")
      Application.put_env(:lex, :llm_timeout_ms, 2_000)

      on_exit(fn ->
        Application.put_env(:lex, :llm_client, original_client)
        Application.put_env(:lex, :llm_api_key, original_api_key)
        Application.put_env(:lex, :llm_base_url, original_base_url)
        Application.put_env(:lex, :llm_timeout_ms, original_timeout)
      end)

      user = create_user()
      document = create_ready_document(user)
      section = create_section(document)
      sentence = create_sentence(section, 1, "Alpha beta gamma.")
      create_tokens_for_sentence(sentence, ["Alpha", "beta", "gamma", "."])

      {:ok, view, _html} = live(conn, "/read/#{document.id}")

      owner_before = llm_connection_owner(view)
      assert is_pid(owner_before)
      assert Process.alive?(owner_before)

      render_hook(view, "key_nav", %{"key" => "w"})
      render_hook(view, "key_nav", %{"key" => "space"})
      Process.sleep(300)

      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "hola"

      render_hook(view, "key_nav", %{"key" => "space"})
      refute view |> has_element?("[data-testid=\"llm-popup\"]")

      render_hook(view, "key_nav", %{"key" => "w"})
      render_hook(view, "key_nav", %{"key" => "space"})
      Process.sleep(300)

      popup_html = view |> element("[data-testid=\"llm-popup\"]") |> render()
      assert popup_html =~ "hola"

      owner_after = llm_connection_owner(view)
      assert owner_after == owner_before
      assert Process.alive?(owner_after)
      assert TestLLMStreamingPlug.request_count() == 2
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

  defp llm_connection_owner(view) do
    :sys.get_state(view.pid).socket.assigns.llm_connection_owner
  end

  defp random_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
