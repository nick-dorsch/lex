defmodule Lex.LLM.Client do
  @moduledoc """
  HTTP client for streaming LLM chat completions.

  Provides a generic interface for OpenAI-compatible streaming APIs using Tesla HTTP client.

  ## Configuration

  By default, this module makes real HTTP requests. For testing, you can configure
  a mock client:

      config :lex, :llm_client, Lex.LLM.ClientMock

  This is automatically set in `config/test.exs`.
  """

  @behaviour Lex.LLM.ClientBehaviour

  require Logger

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

  ## Examples

      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello!"}
      ]

      callback = fn
        {:chunk, content} -> IO.write(content)
        {:done, stats} -> IO.inspect(stats, label: "Done")
        {:error, reason} -> IO.inspect(reason, label: "Error")
      end

      {:ok, task} = Lex.LLM.Client.stream_chat_completion(messages, callback)
  """
  @impl true
  @spec stream_chat_completion(list(message()), chunk_callback()) ::
          {:ok, Task.t()} | {:error, :not_configured}
  def stream_chat_completion(messages, callback)
      when is_list(messages) and is_function(callback, 1) do
    # Allow injection of mock client for testing
    case Application.get_env(:lex, :llm_client) do
      nil -> do_stream_chat_completion(messages, callback)
      __MODULE__ -> do_stream_chat_completion(messages, callback)
      mock_module -> mock_module.stream_chat_completion(messages, callback)
    end
  end

  defp do_stream_chat_completion(messages, callback) do
    api_key = get_config(:llm_api_key)
    base_url = get_config(:llm_base_url)

    if is_nil(api_key) or is_nil(base_url) do
      {:error, :not_configured}
    else
      model = get_config(:llm_model) || "gpt-4o-mini"
      timeout = get_config(:llm_timeout_ms) || 5000

      task =
        Task.async(fn ->
          do_stream_chat_completion(messages, callback, api_key, base_url, model, timeout)
        end)

      {:ok, task}
    end
  end

  defp do_stream_chat_completion(messages, callback, api_key, base_url, model, timeout) do
    url = "#{base_url}/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        model: model,
        messages: messages,
        stream: true
      })

    case make_streaming_request(url, headers, body, timeout, callback) do
      :ok -> :ok
      {:error, reason} -> callback.({:error, reason})
    end
  end

  defp make_streaming_request(url, headers, body, timeout, callback) do
    # Use Mint for streaming HTTP
    uri = URI.parse(url)

    with {:ok, conn} <-
           Mint.HTTP.connect(
             scheme_to_atom(uri.scheme) || :https,
             uri.host,
             uri.port || 443,
             transport_opts: [timeout: timeout]
           ) do
      request_sent_at_ms = System.monotonic_time(:millisecond)

      case Mint.HTTP.request(
             conn,
             "POST",
             uri.path || "/",
             headers,
             body
           ) do
        {:ok, conn, _request_ref} ->
          result =
            stream_response(conn, callback, "", [], timeout, request_sent_at_ms, false)

          Mint.HTTP.close(conn)
          result

        {:error, conn, reason} ->
          Mint.HTTP.close(conn)
          callback.({:error, {:network_error, reason}})

        {:error, reason} ->
          callback.({:error, {:network_error, reason}})
      end
    else
      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        callback.({:error, {:network_error, reason}})

      {:error, reason} ->
        callback.({:error, {:network_error, reason}})
    end
  end

  defp stream_response(
         conn,
         callback,
         buffer,
         chunks_acc,
         timeout,
         request_sent_at_ms,
         first_token_logged
       ) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          :unknown ->
            # Not a Mint message, continue
            stream_response(
              conn,
              callback,
              buffer,
              chunks_acc,
              timeout,
              request_sent_at_ms,
              first_token_logged
            )

          {:ok, conn, responses} ->
            {new_conn, new_buffer, new_chunks_acc, done, new_first_token_logged} =
              process_responses(
                conn,
                responses,
                buffer,
                chunks_acc,
                callback,
                request_sent_at_ms,
                first_token_logged
              )

            if done do
              send_completion_stats(callback, new_chunks_acc)
              :ok
            else
              stream_response(
                new_conn,
                callback,
                new_buffer,
                new_chunks_acc,
                timeout,
                request_sent_at_ms,
                new_first_token_logged
              )
            end

          {:error, conn, error, _responses} ->
            Mint.HTTP.close(conn)
            callback.({:error, {:http_error, error}})
            :error
        end
    after
      timeout ->
        Mint.HTTP.close(conn)
        callback.({:error, :timeout})
        :error
    end
  end

  defp process_responses(
         conn,
         responses,
         buffer,
         chunks_acc,
         callback,
         request_sent_at_ms,
         first_token_logged
       ) do
    Enum.reduce(responses, {conn, buffer, chunks_acc, false, first_token_logged}, fn response,
                                                                                     acc ->
      {conn, buf, chunks, done, token_logged} = acc

      case response do
        {:status, _ref, status} when status >= 400 ->
          {conn, buf, chunks, {:error, {:http_error, status, nil}}, token_logged}

        {:headers, _ref, _headers} ->
          {conn, buf, chunks, done, token_logged}

        {:data, _ref, data} ->
          new_buf = buf <> data

          {new_buf, new_chunks, is_done, new_token_logged} =
            process_sse_data(new_buf, chunks, callback, request_sent_at_ms, token_logged)

          {conn, new_buf, new_chunks, is_done or done, new_token_logged}

        {:done, _ref} ->
          {conn, buf, chunks, true, token_logged}

        _ ->
          {conn, buf, chunks, done, token_logged}
      end
    end)
    |> case do
      {conn, buf, chunks, {:error, reason}, token_logged} ->
        callback.({:error, reason})
        {conn, buf, chunks, true, token_logged}

      other ->
        other
    end
  end

  defp process_sse_data(buffer, chunks_acc, callback, request_sent_at_ms, first_token_logged) do
    buffer
    |> String.split("\n\n", trim: false)
    |> process_sse_lines([], chunks_acc, callback, request_sent_at_ms, first_token_logged)
  end

  defp process_sse_lines(
         [],
         remaining,
         chunks_acc,
         _callback,
         _request_sent_at_ms,
         first_token_logged
       ),
       do: {Enum.join(remaining, "\n\n"), chunks_acc, false, first_token_logged}

  defp process_sse_lines(
         [last],
         [_ | _] = remaining,
         chunks_acc,
         _callback,
         _request_sent_at_ms,
         first_token_logged
       ) do
    # Last incomplete chunk
    {Enum.join(remaining ++ [last], "\n\n"), chunks_acc, false, first_token_logged}
  end

  defp process_sse_lines(
         [_line],
         [],
         chunks_acc,
         _callback,
         _request_sent_at_ms,
         first_token_logged
       ) do
    # Single line that might be incomplete
    {"", chunks_acc, false, first_token_logged}
  end

  defp process_sse_lines(
         [line | rest],
         remaining,
         chunks_acc,
         callback,
         request_sent_at_ms,
         first_token_logged
       ) do
    case parse_sse_line(line) do
      :done ->
        {"", chunks_acc, true, first_token_logged}

      {:chunk, content} ->
        should_log_ttft = not first_token_logged and String.trim(content) != ""

        if should_log_ttft do
          ttft_ms = System.monotonic_time(:millisecond) - request_sent_at_ms
          Logger.info("LLM first token latency: #{ttft_ms}ms")
        end

        callback.({:chunk, content})

        process_sse_lines(
          rest,
          remaining,
          [content | chunks_acc],
          callback,
          request_sent_at_ms,
          first_token_logged or should_log_ttft
        )

      :skip ->
        process_sse_lines(
          rest,
          remaining,
          chunks_acc,
          callback,
          request_sent_at_ms,
          first_token_logged
        )

      :incomplete ->
        process_sse_lines(
          rest,
          remaining ++ [line],
          chunks_acc,
          callback,
          request_sent_at_ms,
          first_token_logged
        )
    end
  end

  defp parse_sse_line(line) do
    line = String.trim(line)

    cond do
      line == "" ->
        :skip

      line == "data: [DONE]" ->
        :done

      String.starts_with?(line, "data: ") ->
        json_str = String.replace_prefix(line, "data: ", "")

        case Jason.decode(json_str) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
            {:chunk, content}

          {:ok, %{"choices" => [%{"delta" => %{}} | _]}} ->
            :skip

          {:ok, _} ->
            :skip

          {:error, _} ->
            :incomplete
        end

      true ->
        :skip
    end
  end

  defp send_completion_stats(callback, chunks) do
    full_content = Enum.reverse(chunks) |> Enum.join("")
    prompt_tokens = estimate_tokens(full_content)
    completion_tokens = estimate_tokens(full_content)

    stats = %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }

    callback.({:done, stats})
  end

  defp estimate_tokens(text) do
    # Rough estimation: ~4 characters per token on average
    ceil(String.length(text) / 4)
  end

  defp scheme_to_atom("https"), do: :https
  defp scheme_to_atom("http"), do: :http
  defp scheme_to_atom(_), do: nil

  defp get_config(key) do
    Application.get_env(:lex, key)
  end
end
