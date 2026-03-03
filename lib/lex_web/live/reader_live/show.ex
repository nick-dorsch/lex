defmodule LexWeb.ReaderLive.Show do
  use LexWeb, :live_view

  @context_sentence_count 6

  alias Lex.Repo
  alias Lex.Reader
  alias Lex.Vocab
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Text.Token
  alias Lex.Accounts.User

  import Ecto.Query

  @impl true
  def mount(%{"document_id" => document_id}, _session, socket) do
    user_id = 1

    case load_reader_data(user_id, document_id) do
      {:ok,
       %{
         document: document,
         section: section,
         sentence: sentence,
         tokens: tokens,
         lexeme_states: lexeme_states,
         prev_sentences: prev_sentences,
         next_sentences: next_sentences,
         section_progress: section_progress,
         document_progress: document_progress,
         current_user: current_user
       }} ->
        # Mark lexemes as seen and log enter event when sentence is displayed
        if sentence do
          {:ok, _} = Vocab.mark_lexemes_seen(user_id, sentence.id)

          {:ok, _} =
            Reader.log_event(user_id, :enter_sentence, %{
              document_id: document.id,
              section_id: section.id,
              sentence_id: sentence.id
            })
        end

        vocab_counts = load_vocab_counts(user_id)

        {:ok,
         assign(socket,
           document: document,
           section: section,
           sentence: sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           prev_sentences: prev_sentences,
           next_sentences: next_sentences,
           section_progress: section_progress,
           document_progress: document_progress,
           focused_token_index: 0,
           loading: false,
           user_id: user_id,
           current_user: current_user,
           help_requested: false,
           context_sentence_count: @context_sentence_count,
           vocab_counts: vocab_counts,
           llm_popup_visible: false,
           llm_loading: false,
           llm_error: nil,
           llm_content: "",
           llm_content_html: "",
           current_llm_request_id: nil
         )}

      {:error, :document_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Document not found")
         |> redirect(to: ~p"/library")}
    end
  end

  @impl true
  def handle_event("focus_token", %{"token_index" => token_index}, socket) do
    token_index = String.to_integer(token_index)

    if selectable_token_index?(socket.assigns.tokens, token_index) do
      {:noreply, assign(socket, focused_token_index: token_index)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("skip_section", _params, socket) do
    handle_skip_section(socket)
  end

  @impl true
  def handle_event("navigate_to_library", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/library")}
  end

  @impl true
  def handle_event("toggle_learning", %{}, socket) do
    case socket.assigns.focused_token_index do
      0 ->
        {:noreply, socket}

      token_index ->
        token = Enum.at(socket.assigns.tokens, token_index - 1)

        case token && !token.is_punctuation && token.lexeme_id do
          nil ->
            {:noreply, socket}

          lexeme_id ->
            user_id = socket.assigns.user_id
            document = socket.assigns.document
            sentence = socket.assigns.sentence

            # Get current state to check if it changes
            previous_state = Map.get(socket.assigns.lexeme_states, lexeme_id)
            previous_status = if previous_state, do: previous_state.status, else: nil

            case Vocab.toggle_learning(user_id, lexeme_id) do
              {:ok, updated_state} ->
                # Only log event if status actually changed
                if updated_state.status != previous_status do
                  # Determine event type based on new status
                  event_type =
                    if updated_state.status == "learning" do
                      :mark_learning
                    else
                      :unmark_learning
                    end

                  # Log the learning toggle event
                  {:ok, _} =
                    Reader.log_event(user_id, event_type, %{
                      document_id: document.id,
                      sentence_id: sentence.id,
                      token_id: token.id,
                      lexeme_id: lexeme_id,
                      new_status: updated_state.status
                    })
                end

                # Update lexeme_states in assigns
                new_states = Map.put(socket.assigns.lexeme_states, lexeme_id, updated_state)

                {:noreply,
                 assign(socket,
                   lexeme_states: new_states,
                   vocab_counts: load_vocab_counts(user_id)
                 )}

              {:error, _changeset} ->
                {:noreply, put_flash(socket, :error, "Failed to toggle learning state")}
            end
        end
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "l"}, socket) do
    handle_event("toggle_learning", %{}, socket)
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("key_nav", %{"key" => key}, socket) do
    case key do
      "j" ->
        handle_next_sentence(socket)

      "k" ->
        handle_previous_sentence(socket)

      "w" ->
        handle_next_token(socket)

      "b" ->
        handle_previous_token(socket)

      "space" ->
        handle_llm_help(socket)

      "s" ->
        handle_skip_section(socket)

      "l" ->
        handle_event("toggle_learning", %{}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_llm_popup", _params, socket) do
    dismiss_llm_popup(socket)
  end

  # Handles navigation to next token (w key)
  defp handle_next_token(socket) do
    selectable_indices = selectable_token_indices(socket.assigns.tokens)

    new_index = next_selectable_index(selectable_indices, socket.assigns.focused_token_index)

    {:noreply, assign(socket, focused_token_index: new_index)}
  end

  # Handles navigation to previous token (b key)
  defp handle_previous_token(socket) do
    selectable_indices = selectable_token_indices(socket.assigns.tokens)

    new_index = previous_selectable_index(selectable_indices, socket.assigns.focused_token_index)

    {:noreply, assign(socket, focused_token_index: new_index)}
  end

  # Handles navigation to the next sentence (j key)
  defp handle_next_sentence(socket) do
    user_id = socket.assigns.user_id
    document = socket.assigns.document
    section = socket.assigns.section
    sentence = socket.assigns.sentence

    case Reader.next_sentence(document.id, section.id, sentence.id) do
      {:ok, %{section: new_section, sentence: new_sentence}} ->
        # Wrap all state changes in a transaction for consistency
        {:ok, _} =
          Repo.transaction(fn ->
            # 1. Promote seen lexemes to known for current sentence
            {:ok, _} = Vocab.promote_seen_to_known(user_id, sentence.id)

            # 2. Mark current sentence as read
            {:ok, _} = Reader.mark_sentence_read(user_id, sentence.id)

            # 3. Update reading position
            {:ok, _} =
              Reader.set_position(user_id, document.id, new_section.id, new_sentence.id)

            # 4. Log the advance event
            {:ok, _} =
              Reader.log_event(user_id, :advance_sentence, %{
                document_id: document.id,
                from_sentence_id: sentence.id,
                to_sentence_id: new_sentence.id,
                from_section_id: section.id,
                to_section_id: new_section.id
              })

            # 5. Mark lexemes as seen for new sentence
            {:ok, _} = Vocab.mark_lexemes_seen(user_id, new_sentence.id)

            :ok
          end)

        # Load tokens for new sentence (outside transaction)
        tokens = load_tokens(new_sentence.id)
        lexeme_ids = Enum.map(tokens, & &1.lexeme_id) |> Enum.reject(&is_nil/1)
        lexeme_states = load_lexeme_states(user_id, lexeme_ids)

        # Load new context sentences for display
        prev_sentences =
          load_context_sentences(
            document.id,
            new_section.id,
            new_sentence.id,
            :previous,
            @context_sentence_count
          )

        next_sentences =
          load_context_sentences(
            document.id,
            new_section.id,
            new_sentence.id,
            :next,
            @context_sentence_count
          )

        # Calculate new progress
        {:ok, new_section_progress} = Reader.get_section_progress(new_section.id, new_sentence.id)
        {:ok, new_document_progress} = Reader.get_document_progress(document.id, new_sentence.id)

        {:noreply,
         socket
         |> assign(
           section: new_section,
           sentence: new_sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           prev_sentences: prev_sentences,
           next_sentences: next_sentences,
           section_progress: new_section_progress,
           document_progress: new_document_progress,
           focused_token_index: 0,
           help_requested: false,
           vocab_counts: load_vocab_counts(user_id)
         )}

      {:error, :end_of_document} ->
        # Stay at current position (could show a flash message)
        {:noreply, socket}
    end
  end

  # Handles navigation to the previous sentence (k key)
  defp handle_previous_sentence(socket) do
    user_id = socket.assigns.user_id
    document = socket.assigns.document
    section = socket.assigns.section
    sentence = socket.assigns.sentence

    case Reader.previous_sentence(document.id, section.id, sentence.id) do
      {:ok, %{section: new_section, sentence: new_sentence}} ->
        # Note: Backward navigation does NOT:
        # - Promote seen words to known
        # - Mark sentences as read
        # - Log events (too noisy)
        # It only updates position and loads new sentence

        # Update reading position
        {:ok, _} =
          Reader.set_position(user_id, document.id, new_section.id, new_sentence.id)

        # Load tokens for new sentence
        tokens = load_tokens(new_sentence.id)
        lexeme_ids = Enum.map(tokens, & &1.lexeme_id) |> Enum.reject(&is_nil/1)
        lexeme_states = load_lexeme_states(user_id, lexeme_ids)

        # Load new context sentences for display
        prev_sentences =
          load_context_sentences(
            document.id,
            new_section.id,
            new_sentence.id,
            :previous,
            @context_sentence_count
          )

        next_sentences =
          load_context_sentences(
            document.id,
            new_section.id,
            new_sentence.id,
            :next,
            @context_sentence_count
          )

        # Calculate new progress
        {:ok, new_section_progress} = Reader.get_section_progress(new_section.id, new_sentence.id)
        {:ok, new_document_progress} = Reader.get_document_progress(document.id, new_sentence.id)

        {:noreply,
         socket
         |> assign(
           section: new_section,
           sentence: new_sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           prev_sentences: prev_sentences,
           next_sentences: next_sentences,
           section_progress: new_section_progress,
           document_progress: new_document_progress,
           focused_token_index: 0,
           help_requested: false,
           vocab_counts: load_vocab_counts(user_id)
         )}

      {:error, :start_of_document} ->
        # Stay at current position
        {:noreply, socket}
    end
  end

  # Handles skip section navigation (s key)
  defp handle_skip_section(socket) do
    user_id = socket.assigns.user_id
    document = socket.assigns.document
    section = socket.assigns.section
    sentence = socket.assigns.sentence

    case Reader.skip_to_next_section(document.id, section.id, sentence.id) do
      {:ok, %{section: new_section, sentence: new_sentence, skipped_sentences: skipped}} ->
        # Wrap state changes in transaction
        {:ok, _} =
          Repo.transaction(fn ->
            # 1. Log the skip event (but DON'T promote or mark as read)
            {:ok, _} =
              Reader.log_event(user_id, :skip_range, %{
                document_id: document.id,
                from_section_id: section.id,
                to_section_id: new_section.id,
                from_sentence_id: sentence.id,
                to_sentence_id: new_sentence.id,
                skipped_sentences: skipped
              })

            # 2. Update reading position
            {:ok, _} =
              Reader.set_position(user_id, document.id, new_section.id, new_sentence.id)

            # 3. Mark lexemes as seen for new sentence (no promotion for skipped sections)
            {:ok, _} = Vocab.mark_lexemes_seen(user_id, new_sentence.id)

            :ok
          end)

        # Load tokens for new sentence (outside transaction)
        tokens = load_tokens(new_sentence.id)
        lexeme_ids = Enum.map(tokens, & &1.lexeme_id) |> Enum.reject(&is_nil/1)
        lexeme_states = load_lexeme_states(user_id, lexeme_ids)

        # Load new context sentences for display
        prev_sentences =
          load_context_sentences(
            document.id,
            new_section.id,
            new_sentence.id,
            :previous,
            @context_sentence_count
          )

        next_sentences =
          load_context_sentences(
            document.id,
            new_section.id,
            new_sentence.id,
            :next,
            @context_sentence_count
          )

        # Calculate new progress
        {:ok, new_section_progress} = Reader.get_section_progress(new_section.id, new_sentence.id)
        {:ok, new_document_progress} = Reader.get_document_progress(document.id, new_sentence.id)

        {:noreply,
         socket
         |> assign(
           section: new_section,
           sentence: new_sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           prev_sentences: prev_sentences,
           next_sentences: next_sentences,
           section_progress: new_section_progress,
           document_progress: new_document_progress,
           focused_token_index: 0,
           help_requested: false
         )}

      {:error, :end_of_document} ->
        # Stay at current position
        {:noreply, socket}
    end
  end

  # Handles LLM help request when spacebar is pressed
  defp handle_llm_help(socket) do
    # If popup is visible, hide it (toggle off)
    if socket.assigns.llm_popup_visible do
      dismiss_llm_popup(socket)
    else
      start_llm_help_request(socket)
    end
  end

  # Dismisses the LLM popup and clears state
  defp dismiss_llm_popup(socket) do
    {:noreply,
     socket
     |> assign(
       llm_popup_visible: false,
       llm_content: "",
       llm_content_html: "",
       llm_error: nil,
       current_llm_request_id: nil,
       llm_loading: false
     )}
  end

  # Starts a new LLM help request
  defp start_llm_help_request(socket) do
    user_id = socket.assigns.user_id
    document = socket.assigns.document
    sentence = socket.assigns.sentence

    case socket.assigns.focused_token_index do
      0 ->
        # No focused token - request sentence-level help
        handle_sentence_level_help(socket, user_id, document, sentence)

      token_index ->
        # Focused token exists - request token-level help
        handle_token_level_help(socket, user_id, document, sentence, token_index)
    end
  end

  defp handle_sentence_level_help(socket, user_id, document, sentence) do
    case Vocab.log_llm_request(user_id, document.id, sentence.id, nil, :sentence) do
      {:ok, request} ->
        # Log the reading event
        {:ok, _} =
          Reader.log_event(user_id, :llm_help_requested, %{
            document_id: document.id,
            sentence_id: sentence.id,
            request_type: :sentence
          })

        # For now, sentence-level help just shows the popup without streaming
        # (can be extended later to call LLM)
        {:noreply,
         assign(socket,
           help_requested: true,
           llm_popup_visible: true,
           llm_loading: false,
           llm_content: "Sentence-level help coming soon...",
           llm_content_html: render_markdown_html("Sentence-level help coming soon..."),
           current_llm_request_id: request.id
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to request help")}
    end
  end

  defp handle_token_level_help(socket, user_id, document, sentence, token_index) do
    token = Enum.at(socket.assigns.tokens, token_index - 1)

    case token && !token.is_punctuation && token.lexeme_id do
      nil ->
        {:noreply, socket}

      lexeme_id ->
        token_id = token.id

        # Advance help state (seen -> learning -> known)
        case Vocab.advance_help_state(user_id, lexeme_id) do
          {:ok, updated_state} ->
            # Update lexeme_states in assigns immediately
            new_states = Map.put(socket.assigns.lexeme_states, lexeme_id, updated_state)

            socket =
              assign(socket, lexeme_states: new_states, vocab_counts: load_vocab_counts(user_id))

            # Start LLM request with streaming
            # Capture the LiveView PID to ensure messages go to the right process
            live_view_pid = self()

            stream_callback = fn event ->
              send(live_view_pid, Tuple.insert_at(event, 0, :llm_event))
            end

            case Vocab.request_llm_help(
                   user_id,
                   document.id,
                   sentence.id,
                   token_id,
                   stream_callback
                 ) do
              {:ok, request_id, start_time} ->
                # Log the reading event
                {:ok, _} =
                  Reader.log_event(user_id, :llm_help_requested, %{
                    document_id: document.id,
                    sentence_id: sentence.id,
                    token_id: token_id,
                    lexeme_id: lexeme_id,
                    request_type: :token
                  })

                {:noreply,
                 assign(socket,
                   help_requested: true,
                   llm_popup_visible: true,
                   llm_loading: true,
                   llm_content: "",
                   llm_content_html: "",
                   llm_error: nil,
                   current_llm_request_id: request_id,
                   current_llm_start_time: start_time
                 )}

              {:error, reason} ->
                error_message = llm_error_to_message(reason)

                {:noreply,
                 socket
                 |> assign(
                   llm_popup_visible: true,
                   llm_loading: false,
                   llm_error: error_message
                 )
                 |> push_event("llm_error", %{message: error_message})}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update word status")}
        end
    end
  end

  defp llm_error_to_message(:not_configured), do: "LLM not configured. Please contact support."
  defp llm_error_to_message(:user_not_found), do: "User not found."
  defp llm_error_to_message(:token_not_found), do: "Token not found."
  defp llm_error_to_message(:required_data_not_found), do: "Required data not found."
  defp llm_error_to_message(:timeout), do: "LLM request timed out. Please try again."

  defp llm_error_to_message({:network_error, :timeout}),
    do: "LLM request timed out. Please try again."

  defp llm_error_to_message({:http_error, 401, _}),
    do: "LLM authentication failed. Please verify API credentials."

  defp llm_error_to_message({:http_error, 429, _}),
    do: "LLM rate limit reached. Please try again shortly."

  defp llm_error_to_message(_), do: "An error occurred while requesting help."

  # Handle LLM streaming chunks
  @impl true
  def handle_info({:llm_event, :chunk, content}, socket) do
    request_id = socket.assigns.current_llm_request_id

    new_content = socket.assigns.llm_content <> content

    {:noreply,
     socket
     |> assign(
       llm_content: new_content,
       llm_content_html: render_markdown_html(new_content)
     )
     |> push_event("llm_chunk", %{content: content, request_id: request_id})}
  end

  # Handle cached LLM response (immediate, no streaming)
  @impl true
  def handle_info({:llm_event, :cached, response_text}, socket) do
    request_id = socket.assigns.current_llm_request_id

    {:noreply,
     socket
     |> assign(
       llm_content: response_text,
       llm_content_html: render_markdown_html(response_text),
       llm_loading: false
     )
     |> push_event("llm_chunk", %{content: response_text, request_id: request_id})
     |> push_event("llm_done", %{})}
  end

  # Handle LLM streaming completion
  @impl true
  def handle_info({:llm_event, :done, stats}, socket) do
    request_id = socket.assigns.current_llm_request_id

    # Finalize the request record with stats
    if request_id do
      Vocab.finalize_llm_request(
        request_id,
        socket.assigns.llm_content,
        stats[:latency_ms],
        stats[:prompt_tokens],
        stats[:completion_tokens]
      )
    end

    {:noreply,
     socket
     |> assign(llm_loading: false)
     |> push_event("llm_done", %{})}
  end

  # Handle LLM streaming errors
  @impl true
  def handle_info({:llm_event, :error, reason}, socket) do
    error_message = llm_error_to_message(reason)

    # Finalize the request with latency if we have a request ID and start time
    request_id = socket.assigns.current_llm_request_id
    start_time = socket.assigns.current_llm_start_time

    if request_id && start_time do
      latency_ms = System.monotonic_time(:millisecond) - start_time
      Vocab.finalize_llm_request(request_id, nil, latency_ms, nil, nil)
    end

    {:noreply,
     socket
     |> assign(
       llm_error: error_message,
       llm_loading: false
     )
     |> push_event("llm_error", %{message: error_message})}
  end

  # Catch-all to handle Task completion messages and other unexpected messages
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_reader_data(user_id, document_id) do
    with {:ok, position} <- Reader.get_or_create_position(user_id, document_id),
         document when not is_nil(document) <- Repo.get(Document, document_id),
         current_user when not is_nil(current_user) <- Repo.get(User, user_id) do
      section = position.section_id && Repo.get(Section, position.section_id)
      sentence = position.sentence_id && Repo.get(Sentence, position.sentence_id)

      tokens =
        if sentence do
          load_tokens(sentence.id)
        else
          []
        end

      lexeme_ids = Enum.map(tokens, & &1.lexeme_id) |> Enum.reject(&is_nil/1)
      lexeme_states = load_lexeme_states(user_id, lexeme_ids)

      # Load context sentences around current sentence
      {prev_sentences, next_sentences} =
        if sentence && section do
          {
            load_context_sentences(
              document.id,
              section.id,
              sentence.id,
              :previous,
              @context_sentence_count
            ),
            load_context_sentences(
              document.id,
              section.id,
              sentence.id,
              :next,
              @context_sentence_count
            )
          }
        else
          {[], []}
        end

      # Calculate progress percentages
      {section_progress, document_progress} =
        if sentence && section do
          {:ok, sec_prog} = Reader.get_section_progress(section.id, sentence.id)
          {:ok, doc_prog} = Reader.get_document_progress(document.id, sentence.id)
          {sec_prog, doc_prog}
        else
          {0.0, 0.0}
        end

      {:ok,
       %{
         document: document,
         section: section,
         sentence: sentence,
         tokens: tokens,
         lexeme_states: lexeme_states,
         prev_sentences: prev_sentences,
         next_sentences: next_sentences,
         section_progress: section_progress,
         document_progress: document_progress,
         current_user: current_user
       }}
    else
      {:error, :document_not_found} -> {:error, :document_not_found}
      nil -> {:error, :document_not_found}
    end
  end

  defp load_context_sentences(document_id, section_id, sentence_id, direction, count) do
    sentences =
      do_load_context_sentences(document_id, section_id, sentence_id, direction, count, [])

    if direction == :previous do
      Enum.reverse(sentences)
    else
      sentences
    end
  end

  defp do_load_context_sentences(_document_id, _section_id, _sentence_id, _direction, 0, acc),
    do: acc

  defp do_load_context_sentences(document_id, section_id, sentence_id, direction, remaining, acc) do
    result =
      case direction do
        :previous -> Reader.previous_sentence(document_id, section_id, sentence_id)
        :next -> Reader.next_sentence(document_id, section_id, sentence_id)
      end

    case result do
      {:ok, %{section: next_section, sentence: next_sentence}} ->
        do_load_context_sentences(
          document_id,
          next_section.id,
          next_sentence.id,
          direction,
          remaining - 1,
          acc ++ [next_sentence]
        )

      {:error, _} ->
        acc
    end
  end

  defp load_tokens(sentence_id) do
    Token
    |> where(sentence_id: ^sentence_id)
    |> order_by(asc: :position)
    |> Repo.all()
  end

  defp load_lexeme_states(user_id, lexeme_ids) do
    alias Lex.Vocab.UserLexemeState

    if lexeme_ids == [] do
      %{}
    else
      UserLexemeState
      |> where([s], s.user_id == ^user_id and s.lexeme_id in ^lexeme_ids)
      |> Repo.all()
      |> Map.new(fn state -> {state.lexeme_id, state} end)
    end
  end

  defp load_vocab_counts(user_id) do
    Vocab.get_status_counts(user_id)
  end

  defp selectable_token_indices(tokens) do
    tokens
    |> Enum.with_index(1)
    |> Enum.filter(fn {token, _index} -> not token.is_punctuation end)
    |> Enum.map(fn {_token, index} -> index end)
  end

  defp selectable_token_index?(tokens, token_index) do
    token = Enum.at(tokens, token_index - 1)
    token && not token.is_punctuation
  end

  defp next_selectable_index([], _current_index), do: 0

  defp next_selectable_index(selectable_indices, current_index) do
    Enum.find(selectable_indices, fn index -> index > current_index end) || hd(selectable_indices)
  end

  defp previous_selectable_index([], _current_index), do: 0

  defp previous_selectable_index(selectable_indices, current_index) do
    selectable_indices
    |> Enum.reverse()
    |> Enum.find(fn index -> index < current_index end) || List.last(selectable_indices)
  end

  defp render_markdown_html(content) when content in [nil, ""], do: ""

  defp render_markdown_html(content) when is_binary(content) do
    content
    |> Earmark.as_html!()
    |> HtmlSanitizeEx.basic_html()
  end
end
