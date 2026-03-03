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

  alias Lex.LLM.SessionConnectionOwner

  @type message :: %{role: String.t(), content: String.t()}
  @type chunk_callback ::
          ({:chunk, String.t()} | {:done, map()} | {:error, term()} -> any())
  @type stream_opt :: {:connection_owner, GenServer.server()}
  @type transport_path :: :newly_connected | :reused | :reconnected_after_retry

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
    stream_chat_completion(messages, callback, [])
  end

  @spec stream_chat_completion(list(message()), chunk_callback(), [stream_opt()]) ::
          {:ok, Task.t()} | {:error, :not_configured}
  def stream_chat_completion(messages, callback, opts)
      when is_list(messages) and is_function(callback, 1) do
    # Allow injection of mock client for testing
    case Application.get_env(:lex, :llm_client) do
      nil ->
        do_stream_chat_completion(messages, callback, opts)

      __MODULE__ ->
        do_stream_chat_completion(messages, callback, opts)

      mock_module ->
        if function_exported?(mock_module, :stream_chat_completion, 3) do
          mock_module.stream_chat_completion(messages, callback, opts)
        else
          mock_module.stream_chat_completion(messages, callback)
        end
    end
  end

  defp do_stream_chat_completion(messages, callback, opts) do
    api_key = get_config(:llm_api_key)
    base_url = get_config(:llm_base_url)

    if is_nil(api_key) or is_nil(base_url) do
      {:error, :not_configured}
    else
      model = get_config(:llm_model) || "gpt-4o-mini"
      timeout = get_config(:llm_timeout_ms) || 5000

      task =
        Task.async(fn ->
          do_stream_chat_completion(messages, callback, api_key, base_url, model, timeout, opts)
        end)

      {:ok, task}
    end
  end

  defp do_stream_chat_completion(messages, callback, api_key, base_url, model, timeout, opts) do
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

    case make_streaming_request(url, headers, body, timeout, callback, opts) do
      :ok -> :ok
      {:error, reason} -> callback.({:error, reason})
    end
  end

  defp make_streaming_request(url, headers, body, timeout, callback, opts) do
    # Use Mint for streaming HTTP
    uri = URI.parse(url)

    with_connection(uri, timeout, opts, fn conn, transport_path ->
      request_sent_at_ms = System.monotonic_time(:millisecond)

      case Mint.HTTP.request(
             conn,
             "POST",
             uri.path || "/",
             headers,
             body
           ) do
        {:ok, conn, _request_ref} ->
          stream_response(
            conn,
            callback,
            "",
            [],
            timeout,
            request_sent_at_ms,
            false,
            false,
            transport_path
          )

        {:error, conn, reason} ->
          Mint.HTTP.close(conn)
          {:error, nil, {:network_error, reason}, recoverable_transport_error?(reason), false}

        {:error, reason} ->
          {:error, nil, {:network_error, reason}, recoverable_transport_error?(reason), false}
      end
    end)
  end

  defp with_connection(uri, timeout, opts, request_fun) do
    case Keyword.get(opts, :connection_owner) do
      nil ->
        with {:ok, conn} <- connect(uri, timeout) do
          finalize_non_owned_connection(request_fun.(conn, :newly_connected), conn)
        end

      owner ->
        connect_fun = fn -> connect(uri, timeout) end
        transport_path = owner_transport_path(owner)
        with_owned_connection(owner, connect_fun, request_fun, 1, transport_path)
    end
  end

  defp finalize_non_owned_connection({:ok, updated_conn}, _original_conn) do
    Mint.HTTP.close(updated_conn)
    :ok
  end

  defp finalize_non_owned_connection(
         {:error, maybe_conn, reason, _retryable?, _chunk_emitted?},
         original_conn
       ) do
    Mint.HTTP.close(maybe_conn || original_conn)
    {:error, reason}
  end

  defp with_owned_connection(owner, connect_fun, request_fun, retries_left, transport_path) do
    with {:ok, conn} <- SessionConnectionOwner.get_or_connect(owner, connect_fun) do
      handle_owned_request_result(
        owner,
        connect_fun,
        request_fun,
        conn,
        retries_left,
        transport_path
      )
    end
  end

  defp handle_owned_request_result(
         owner,
         connect_fun,
         request_fun,
         conn,
         retries_left,
         transport_path
       ) do
    case request_fun.(conn, transport_path) do
      {:ok, updated_conn} ->
        with :ok <- return_connection_to_owner(updated_conn, owner) do
          :ok = SessionConnectionOwner.put_connection(owner, updated_conn)
          :ok
        end

      {:error, reason} ->
        :ok = SessionConnectionOwner.mark_unhealthy(owner, reason)
        {:error, reason}

      {:error, _maybe_conn, _reason, _retryable?, _chunk_emitted?} = error_tuple ->
        handle_owned_request_error(
          owner,
          connect_fun,
          request_fun,
          retries_left,
          error_tuple
        )
    end
  end

  defp handle_owned_request_error(
         owner,
         connect_fun,
         request_fun,
         retries_left,
         {:error, maybe_conn, reason, retryable?, chunk_emitted?}
       ) do
    if maybe_conn, do: Mint.HTTP.close(maybe_conn)

    should_retry = retries_left > 0 and retryable? and not chunk_emitted?

    if should_retry do
      Logger.info(
        "LLM reconnect attempt after transport failure: reason=#{inspect(reason)} retries_left=#{retries_left}"
      )

      :ok = SessionConnectionOwner.mark_unhealthy(owner, reason)

      case SessionConnectionOwner.reconnect(owner, connect_fun) do
        {:ok, _conn} ->
          Logger.info("LLM reconnect succeeded")

          with_owned_connection(
            owner,
            connect_fun,
            request_fun,
            retries_left - 1,
            :reconnected_after_retry
          )

        {:error, reconnect_reason} ->
          Logger.info("LLM reconnect failed: reason=#{inspect(reconnect_reason)}")
          {:error, reconnect_reason}
      end
    else
      :ok = SessionConnectionOwner.mark_unhealthy(owner, reason)
      {:error, reason}
    end
  end

  defp owner_transport_path(owner) do
    if SessionConnectionOwner.current_connection(owner) do
      :reused
    else
      :newly_connected
    end
  end

  defp return_connection_to_owner(conn, owner) do
    case Mint.HTTP.controlling_process(conn, owner) do
      :ok ->
        :ok

      {:ok, _conn} ->
        :ok

      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        {:error, {:network_error, reason}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp connect(uri, timeout) do
    case Mint.HTTP.connect(
           scheme_to_atom(uri.scheme) || :https,
           uri.host,
           uri.port || 443,
           transport_opts: [timeout: timeout]
         ) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        {:error, {:network_error, reason}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp stream_response(
         conn,
         callback,
         buffer,
         chunks_acc,
         timeout,
         request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         transport_path
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
              first_token_logged,
              chunk_emitted,
              transport_path
            )

          {:ok, conn, responses} ->
            {new_conn, new_buffer, new_chunks_acc, done, new_first_token_logged,
             new_chunk_emitted} =
              process_responses(
                conn,
                responses,
                buffer,
                chunks_acc,
                callback,
                request_sent_at_ms,
                first_token_logged,
                chunk_emitted,
                transport_path
              )

            case done do
              true ->
                send_completion_stats(callback, new_chunks_acc)
                {:ok, new_conn}

              {:error, reason, retryable?} ->
                {:error, new_conn, reason, retryable?, new_chunk_emitted}

              false ->
                stream_response(
                  new_conn,
                  callback,
                  new_buffer,
                  new_chunks_acc,
                  timeout,
                  request_sent_at_ms,
                  new_first_token_logged,
                  new_chunk_emitted,
                  transport_path
                )
            end

          {:error, conn, error, _responses} ->
            Mint.HTTP.close(conn)

            {:error, nil, {:http_error, error}, recoverable_transport_error?(error),
             chunk_emitted}
        end
    after
      timeout ->
        Mint.HTTP.close(conn)
        {:error, nil, :timeout, true, chunk_emitted}
    end
  end

  defp process_responses(
         conn,
         responses,
         buffer,
         chunks_acc,
         callback,
         request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         transport_path
       ) do
    Enum.reduce(
      responses,
      {conn, buffer, chunks_acc, false, first_token_logged, chunk_emitted},
      fn response, acc ->
        {conn, buf, chunks, done, token_logged, emitted_chunk?} = acc

        case response do
          {:status, _ref, status} when status >= 400 ->
            {conn, buf, chunks, {:error, {:http_error, status, nil}, false}, token_logged,
             emitted_chunk?}

          {:headers, _ref, _headers} ->
            {conn, buf, chunks, done, token_logged, emitted_chunk?}

          {:data, _ref, data} ->
            new_buf = buf <> data

            {new_buf, new_chunks, is_done, new_token_logged, new_emitted_chunk?} =
              process_sse_data(
                new_buf,
                chunks,
                callback,
                request_sent_at_ms,
                token_logged,
                emitted_chunk?,
                transport_path
              )

            {conn, new_buf, new_chunks, merge_done(done, is_done), new_token_logged,
             new_emitted_chunk?}

          {:done, _ref} ->
            {conn, buf, chunks, merge_done(done, true), token_logged, emitted_chunk?}

          _ ->
            {conn, buf, chunks, done, token_logged, emitted_chunk?}
        end
      end
    )
  end

  defp process_sse_data(
         buffer,
         chunks_acc,
         callback,
         request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         transport_path
       ) do
    buffer
    |> String.split("\n\n", trim: false)
    |> process_sse_lines(
      [],
      chunks_acc,
      callback,
      request_sent_at_ms,
      first_token_logged,
      chunk_emitted,
      transport_path
    )
  end

  defp process_sse_lines(
         [],
         remaining,
         chunks_acc,
         _callback,
         _request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         _transport_path
       ),
       do: {Enum.join(remaining, "\n\n"), chunks_acc, false, first_token_logged, chunk_emitted}

  defp process_sse_lines(
         [last],
         [_ | _] = remaining,
         chunks_acc,
         _callback,
         _request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         _transport_path
       ) do
    # Last incomplete chunk
    {Enum.join(remaining ++ [last], "\n\n"), chunks_acc, false, first_token_logged, chunk_emitted}
  end

  defp process_sse_lines(
         [_line],
         [],
         chunks_acc,
         _callback,
         _request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         _transport_path
       ) do
    # Single line that might be incomplete
    {"", chunks_acc, false, first_token_logged, chunk_emitted}
  end

  defp process_sse_lines(
         [line | rest],
         remaining,
         chunks_acc,
         callback,
         request_sent_at_ms,
         first_token_logged,
         chunk_emitted,
         transport_path
       ) do
    case parse_sse_line(line) do
      :done ->
        {"", chunks_acc, true, first_token_logged, chunk_emitted}

      {:chunk, content} ->
        should_log_ttft = not first_token_logged and String.trim(content) != ""

        if should_log_ttft do
          ttft_ms = System.monotonic_time(:millisecond) - request_sent_at_ms

          Logger.info("LLM first token latency: #{ttft_ms}ms (transport_path=#{transport_path})")
        end

        callback.({:chunk, content})

        process_sse_lines(
          rest,
          remaining,
          [content | chunks_acc],
          callback,
          request_sent_at_ms,
          first_token_logged or should_log_ttft,
          true,
          transport_path
        )

      :skip ->
        process_sse_lines(
          rest,
          remaining,
          chunks_acc,
          callback,
          request_sent_at_ms,
          first_token_logged,
          chunk_emitted,
          transport_path
        )

      :incomplete ->
        process_sse_lines(
          rest,
          remaining ++ [line],
          chunks_acc,
          callback,
          request_sent_at_ms,
          first_token_logged,
          chunk_emitted,
          transport_path
        )
    end
  end

  defp recoverable_transport_error?(reason)

  defp recoverable_transport_error?(reason)
       when reason in [
              :closed,
              :timeout,
              :econnreset,
              :econnaborted,
              :enetdown,
              :ehostdown,
              :ehostunreach,
              :closed_for_writing
            ],
       do: true

  defp recoverable_transport_error?({:closed, _}), do: true
  defp recoverable_transport_error?({:tcp_closed, _}), do: true
  defp recoverable_transport_error?({:tls_closed, _}), do: true
  defp recoverable_transport_error?(%Mint.TransportError{}), do: true
  defp recoverable_transport_error?(_reason), do: false

  defp merge_done({:error, _reason, _retryable?} = error, _is_done), do: error
  defp merge_done(done, false), do: done
  defp merge_done(_done, true), do: true

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
