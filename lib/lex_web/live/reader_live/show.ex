defmodule LexWeb.ReaderLive.Show do
  use LexWeb, :live_view

  alias Lex.Repo
  alias Lex.Reader
  alias Lex.Vocab
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Text.Sentence
  alias Lex.Text.Token

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
         lexeme_states: lexeme_states
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

        {:ok,
         assign(socket,
           document: document,
           section: section,
           sentence: sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           focused_token_index: 0,
           loading: false,
           user_id: user_id,
           help_requested: false
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
    {:noreply, assign(socket, focused_token_index: token_index)}
  end

  @impl true
  def handle_event("skip_section", _params, socket) do
    handle_skip_section(socket)
  end

  @impl true
  def handle_event("toggle_learning", %{}, socket) do
    case socket.assigns.focused_token_index do
      0 ->
        {:noreply, socket}

      token_index ->
        token = Enum.at(socket.assigns.tokens, token_index - 1)

        case token && token.lexeme_id do
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
                {:noreply, assign(socket, lexeme_states: new_states)}

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

  # Handles navigation to next token (w key)
  defp handle_next_token(socket) do
    tokens = socket.assigns.tokens
    token_count = length(tokens)

    new_index =
      case socket.assigns.focused_token_index do
        0 -> 1
        current when current >= token_count -> 1
        current -> current + 1
      end

    {:noreply, assign(socket, focused_token_index: new_index)}
  end

  # Handles navigation to previous token (b key)
  defp handle_previous_token(socket) do
    tokens = socket.assigns.tokens
    token_count = length(tokens)

    new_index =
      case socket.assigns.focused_token_index do
        0 -> token_count
        1 -> token_count
        current -> current - 1
      end

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

        {:noreply,
         socket
         |> assign(
           section: new_section,
           sentence: new_sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           focused_token_index: 0,
           help_requested: false
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

        {:noreply,
         socket
         |> assign(
           section: new_section,
           sentence: new_sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           focused_token_index: 0,
           help_requested: false
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

        {:noreply,
         socket
         |> assign(
           section: new_section,
           sentence: new_sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
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
    user_id = socket.assigns.user_id
    document = socket.assigns.document
    sentence = socket.assigns.sentence

    case socket.assigns.focused_token_index do
      0 ->
        # No focused token - request sentence-level help
        case Vocab.log_llm_request(user_id, document.id, sentence.id, nil, :sentence) do
          {:ok, _} ->
            # Log the reading event
            {:ok, _} =
              Reader.log_event(user_id, :llm_help_requested, %{
                document_id: document.id,
                sentence_id: sentence.id,
                request_type: :sentence
              })

            {:noreply, assign(socket, help_requested: true)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to request help")}
        end

      token_index ->
        # Focused token exists - mark as learning and request token-level help
        token = Enum.at(socket.assigns.tokens, token_index - 1)
        token_id = token.id

        case token && token.lexeme_id do
          nil ->
            {:noreply, socket}

          lexeme_id ->
            # Mark as learning
            case Vocab.mark_learning(user_id, lexeme_id) do
              {:ok, updated_state} ->
                # Log LLM request
                case Vocab.log_llm_request(
                       user_id,
                       document.id,
                       sentence.id,
                       token_id,
                       :token
                     ) do
                  {:ok, _} ->
                    # Log the reading event
                    {:ok, _} =
                      Reader.log_event(user_id, :llm_help_requested, %{
                        document_id: document.id,
                        sentence_id: sentence.id,
                        token_id: token_id,
                        lexeme_id: lexeme_id,
                        request_type: :token
                      })

                    # Update lexeme_states in assigns
                    new_states = Map.put(socket.assigns.lexeme_states, lexeme_id, updated_state)

                    {:noreply,
                     socket
                     |> assign(lexeme_states: new_states)
                     |> assign(help_requested: true)}

                  {:error, _} ->
                    {:noreply, put_flash(socket, :error, "Failed to request help")}
                end

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to mark word as learning")}
            end
        end
    end
  end

  defp load_reader_data(user_id, document_id) do
    with {:ok, position} <- Reader.get_or_create_position(user_id, document_id),
         document when not is_nil(document) <- Repo.get(Document, document_id) do
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

      {:ok,
       %{
         document: document,
         section: section,
         sentence: sentence,
         tokens: tokens,
         lexeme_states: lexeme_states
       }}
    else
      {:error, :document_not_found} -> {:error, :document_not_found}
      nil -> {:error, :document_not_found}
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
end
