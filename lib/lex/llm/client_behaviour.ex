defmodule Lex.LLM.ClientBehaviour do
  @moduledoc """
  Behaviour contract for LLM client implementations.

  Defines the interface for streaming chat completions from LLM APIs.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type chunk_callback ::
          ({:chunk, String.t()} | {:done, map()} | {:error, term()} -> any())

  @doc """
  Stream a chat completion from the LLM API.

  ## Parameters
    - `messages`: List of message maps with `role` ("user" | "system") and `content` fields
    - `callback`: Function that receives streaming events

  ## Callback Events
    - `{:chunk, content}` - A chunk of the completion text
    - `{:done, stats}` - Stream complete with usage stats map
    - `{:error, reason}` - An error occurred

  ## Returns
    - `{:ok, Task.t()}` - The streaming task started successfully
    - `{:error, :not_configured}` - API key or base URL not configured
  """
  @callback stream_chat_completion(list(message()), chunk_callback()) ::
              {:ok, Task.t()} | {:error, :not_configured}
end
