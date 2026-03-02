defmodule Lex.LLM.ClientMock do
  @moduledoc """
  Mock implementation of `Lex.LLM.ClientBehaviour` for testing.

  Simulates streaming chat completions without making external API calls.
  Provides helper functions to configure mock responses and inspect calls.

  ## Configuration

  In `config/test.exs`:
      config :lex, :llm_client, Lex.LLM.ClientMock

  ## Usage

      # Set up a mock response
      Lex.LLM.ClientMock.set_mock_response("Hello from mock!")

      # Or set specific chunks
      Lex.LLM.ClientMock.set_mock_chunks(["Hello, ", "world", "!"])

      # Or simulate an error
      Lex.LLM.ClientMock.set_mock_error(:timeout)

      # After making calls, inspect what was sent
      last_request = Lex.LLM.ClientMock.get_last_request()

      # Clean up after tests
      Lex.LLM.ClientMock.clear_mock()
  """

  @behaviour Lex.LLM.ClientBehaviour

  require Logger

  @default_chunk_delay_ms 50
  @mock_state_key :llm_mock_state

  @type mock_state :: %{
          response: String.t() | nil,
          chunks: list(String.t()) | nil,
          error: term() | nil,
          last_request: list(map()) | nil,
          last_options: keyword(),
          chunk_delay_ms: non_neg_integer()
        }

  # ============================================================================
  # Public API - Behaviour Implementation
  # ============================================================================

  @impl true
  @spec stream_chat_completion(
          list(Lex.LLM.ClientBehaviour.message()),
          Lex.LLM.ClientBehaviour.chunk_callback()
        ) :: {:ok, Task.t()} | {:error, :not_configured}
  def stream_chat_completion(messages, callback)
      when is_list(messages) and is_function(callback, 1) do
    stream_chat_completion(messages, callback, [])
  end

  @spec stream_chat_completion(
          list(Lex.LLM.ClientBehaviour.message()),
          Lex.LLM.ClientBehaviour.chunk_callback(),
          keyword()
        ) :: {:ok, Task.t()} | {:error, :not_configured}
  def stream_chat_completion(messages, callback, opts)
      when is_list(messages) and is_function(callback, 1) do
    state = get_mock_state()

    # Store the request for later inspection
    update_mock_state(%{state | last_request: messages, last_options: opts})

    task =
      Task.async(fn ->
        case state.error do
          nil -> do_stream_response(state, callback)
          reason -> callback.({:error, reason})
        end
      end)

    {:ok, task}
  end

  # ============================================================================
  # Public API - Test Helpers
  # ============================================================================

  @doc """
  Sets the mock response text. The response will be broken into chunks.

  ## Examples

      Lex.LLM.ClientMock.set_mock_response("This is a test response")
  """
  @spec set_mock_response(String.t()) :: :ok
  def set_mock_response(content) when is_binary(content) do
    update_mock_state(%{
      get_mock_state()
      | response: content,
        chunks: nil,
        error: nil
    })

    :ok
  end

  @doc """
  Sets specific chunks to be streamed. Each chunk will be sent as a separate
  `{:chunk, content}` event.

  ## Examples

      Lex.LLM.ClientMock.set_mock_chunks(["Hello, ", "how ", "are ", "you?"])
  """
  @spec set_mock_chunks(list(String.t())) :: :ok
  def set_mock_chunks(chunks) when is_list(chunks) do
    update_mock_state(%{
      get_mock_state()
      | response: nil,
        chunks: chunks,
        error: nil
    })

    :ok
  end

  @doc """
  Sets an error to be returned on the next call.

  ## Examples

      Lex.LLM.ClientMock.set_mock_error(:timeout)
      Lex.LLM.ClientMock.set_mock_error({:http_error, 500})
  """
  @spec set_mock_error(term()) :: :ok
  def set_mock_error(reason) do
    update_mock_state(%{
      get_mock_state()
      | response: nil,
        chunks: nil,
        error: reason
    })

    :ok
  end

  @doc """
  Sets the delay between chunks in milliseconds.

  Defaults to #{@default_chunk_delay_ms}ms.

  ## Examples

      Lex.LLM.ClientMock.set_chunk_delay(100)
  """
  @spec set_chunk_delay(non_neg_integer()) :: :ok
  def set_chunk_delay(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    update_mock_state(%{get_mock_state() | chunk_delay_ms: delay_ms})
    :ok
  end

  @doc """
  Returns the last messages sent to the mock.

  ## Examples

      last_messages = Lex.LLM.ClientMock.get_last_request()
      # => [%{role: "user", content: "Hello"}]
  """
  @spec get_last_request() :: list(map()) | nil
  def get_last_request do
    get_mock_state().last_request
  end

  @doc """
  Returns the last options sent to the mock.
  """
  @spec get_last_options() :: keyword()
  def get_last_options do
    get_mock_state().last_options
  end

  @doc """
  Clears all mock state and resets to defaults.

  ## Examples

      Lex.LLM.ClientMock.clear_mock()
  """
  @spec clear_mock() :: :ok
  def clear_mock do
    # Clear from both process dictionary and persistent term
    Process.delete(@mock_state_key)
    :persistent_term.erase({__MODULE__, :mock_state})
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Use persistent_term for shared state across processes
  defp get_mock_state do
    # First try process dictionary (for backward compatibility in tests)
    case Process.get(@mock_state_key) do
      nil ->
        # Fall back to persistent_term for cross-process access
        case :persistent_term.get({__MODULE__, :mock_state}, :undefined) do
          :undefined ->
            default_state = %{
              response: nil,
              chunks: nil,
              error: nil,
              last_request: nil,
              last_options: [],
              chunk_delay_ms: @default_chunk_delay_ms
            }

            :persistent_term.put({__MODULE__, :mock_state}, default_state)
            default_state

          state ->
            state
        end

      state ->
        state
    end
  end

  defp update_mock_state(new_state) do
    # Update both process dictionary and persistent_term
    Process.put(@mock_state_key, new_state)
    :persistent_term.put({__MODULE__, :mock_state}, new_state)
  end

  defp do_stream_response(state, callback) do
    chunks = get_chunks_to_stream(state)
    delay_ms = state.chunk_delay_ms

    Enum.each(chunks, fn chunk ->
      if delay_ms > 0 do
        Process.sleep(delay_ms)
      end

      callback.({:chunk, chunk})
    end)

    stats = generate_stats(chunks)
    callback.({:done, stats})
  end

  defp get_chunks_to_stream(%{chunks: chunks}) when is_list(chunks) do
    chunks
  end

  defp get_chunks_to_stream(%{response: response}) when is_binary(response) do
    # Break response into word-level chunks for more realistic streaming
    response
    |> String.split(~r/(\s+)/, trim: false, include_captures: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp get_chunks_to_stream(_) do
    ["Mock response: Hello! This is a test response from the mock LLM client."]
  end

  defp generate_stats(chunks) do
    full_content = Enum.join(chunks)
    prompt_tokens = estimate_tokens(full_content)
    completion_tokens = estimate_tokens(full_content)

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end

  defp estimate_tokens(text) do
    # Rough estimation: ~4 characters per token on average
    ceil(String.length(text) / 4)
  end
end
