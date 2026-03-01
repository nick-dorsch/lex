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
        {:ok,
         assign(socket,
           document: document,
           section: section,
           sentence: sentence,
           tokens: tokens,
           lexeme_states: lexeme_states,
           focused_token_id: nil,
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
  def handle_event("focus_token", %{"token_id" => token_id}, socket) do
    token_id = String.to_integer(token_id)
    {:noreply, assign(socket, focused_token_id: token_id)}
  end

  @impl true
  def handle_event("toggle_learning", %{}, socket) do
    case socket.assigns.focused_token_id do
      nil ->
        {:noreply, socket}

      token_id ->
        token = Enum.find(socket.assigns.tokens, fn t -> t.id == token_id end)

        case token && token.lexeme_id do
          nil ->
            {:noreply, socket}

          lexeme_id ->
            case Vocab.toggle_learning(socket.assigns.user_id, lexeme_id) do
              {:ok, updated_state} ->
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
        # Next sentence - stub for now
        {:noreply, socket}

      "k" ->
        # Previous sentence - stub for now
        {:noreply, socket}

      "w" ->
        # Next token - stub for now
        {:noreply, socket}

      "b" ->
        # Previous token - stub for now
        {:noreply, socket}

      "space" ->
        handle_llm_help(socket)

      _ ->
        {:noreply, socket}
    end
  end

  # Handles LLM help request when spacebar is pressed
  defp handle_llm_help(socket) do
    user_id = socket.assigns.user_id
    document = socket.assigns.document
    sentence = socket.assigns.sentence

    case socket.assigns.focused_token_id do
      nil ->
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

      token_id ->
        # Focused token exists - mark as learning and request token-level help
        token = Enum.find(socket.assigns.tokens, fn t -> t.id == token_id end)

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
