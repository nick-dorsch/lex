defmodule Lex.LLM.Client do
  @moduledoc """
  HTTP client for streaming LLM chat completions.

  Provides a generic interface for OpenAI-compatible streaming APIs using Tesla HTTP client.
  """

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
  @spec stream_chat_completion(list(message()), chunk_callback()) ::
          {:ok, Task.t()} | {:error, :not_configured}
  def stream_chat_completion(messages, callback)
      when is_list(messages) and is_function(callback, 1) do
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
           ),
         {:ok, conn, _request_ref} <-
           Mint.HTTP.request(
             conn,
             "POST",
             uri.path || "/",
             headers,
             body
           ) do
      result = stream_response(conn, callback, "", [])
      Mint.HTTP.close(conn)
      result
    else
      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        callback.({:error, {:network_error, reason}})

      {:error, reason} ->
        callback.({:error, {:network_error, reason}})
    end
  end

  defp stream_response(conn, callback, buffer, chunks_acc) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          :unknown ->
            # Not a Mint message, continue
            stream_response(conn, callback, buffer, chunks_acc)

          {:ok, conn, responses} ->
            {new_conn, new_buffer, new_chunks_acc, done} =
              process_responses(conn, responses, buffer, chunks_acc, callback)

            if done do
              send_completion_stats(callback, new_chunks_acc)
              :ok
            else
              stream_response(new_conn, callback, new_buffer, new_chunks_acc)
            end

          {:error, conn, error, _responses} ->
            Mint.HTTP.close(conn)
            callback.({:error, {:http_error, error}})
            :error
        end
    after
      30_000 ->
        Mint.HTTP.close(conn)
        callback.({:error, :timeout})
        :error
    end
  end

  defp process_responses(conn, responses, buffer, chunks_acc, callback) do
    Enum.reduce(responses, {conn, buffer, chunks_acc, false}, fn response, acc ->
      {conn, buf, chunks, done} = acc

      case response do
        {:status, _ref, status} when status >= 400 ->
          {conn, buf, chunks, {:error, {:http_error, status, nil}}}

        {:headers, _ref, _headers} ->
          {conn, buf, chunks, done}

        {:data, _ref, data} ->
          new_buf = buf <> data
          {new_buf, new_chunks, is_done} = process_sse_data(new_buf, chunks, callback)
          {conn, new_buf, new_chunks, is_done or done}

        {:done, _ref} ->
          {conn, buf, chunks, true}

        _ ->
          {conn, buf, chunks, done}
      end
    end)
    |> case do
      {conn, buf, chunks, {:error, reason}} ->
        callback.({:error, reason})
        {conn, buf, chunks, true}

      other ->
        other
    end
  end

  defp process_sse_data(buffer, chunks_acc, callback) do
    buffer
    |> String.split("\n\n", trim: false)
    |> process_sse_lines([], chunks_acc, callback)
  end

  defp process_sse_lines([], remaining, chunks_acc, _callback),
    do: {Enum.join(remaining, "\n\n"), chunks_acc, false}

  defp process_sse_lines([last], [_ | _] = remaining, chunks_acc, _callback) do
    # Last incomplete chunk
    {Enum.join(remaining ++ [last], "\n\n"), chunks_acc, false}
  end

  defp process_sse_lines([_line], [], chunks_acc, _callback) do
    # Single line that might be incomplete
    {"", chunks_acc, false}
  end

  defp process_sse_lines([line | rest], remaining, chunks_acc, callback) do
    case parse_sse_line(line) do
      :done ->
        {"", chunks_acc, true}

      {:chunk, content} ->
        callback.({:chunk, content})
        process_sse_lines(rest, remaining, [content | chunks_acc], callback)

      :skip ->
        process_sse_lines(rest, remaining, chunks_acc, callback)

      :incomplete ->
        process_sse_lines(rest, remaining ++ [line], chunks_acc, callback)
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
        json_str = String.slice(line, 6..-1)

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
