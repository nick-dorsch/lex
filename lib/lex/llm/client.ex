defmodule Lex.LLM.Client do
  @moduledoc """
  HTTP client for LLM chat completions.

  Provides a generic interface for OpenAI-compatible chat APIs.

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
    stream_chat_completion(messages, callback, [])
  end

  @spec stream_chat_completion(list(message()), chunk_callback(), keyword()) ::
          {:ok, Task.t()} | {:error, :not_configured}
  def stream_chat_completion(messages, callback, opts)
      when is_list(messages) and is_function(callback, 1) do
    # Allow injection of mock client for testing
    case Application.get_env(:lex, :llm_client) do
      nil ->
        do_chat_completion(messages, callback, opts)

      __MODULE__ ->
        do_chat_completion(messages, callback, opts)

      mock_module ->
        if function_exported?(mock_module, :stream_chat_completion, 3) do
          mock_module.stream_chat_completion(messages, callback, opts)
        else
          mock_module.stream_chat_completion(messages, callback)
        end
    end
  end

  defp do_chat_completion(messages, callback, _opts) do
    api_key = get_config(:llm_api_key)
    base_url = get_config(:llm_base_url)

    if is_nil(api_key) or is_nil(base_url) do
      {:error, :not_configured}
    else
      model = get_config(:llm_model) || "gpt-4o-mini"
      timeout = get_config(:llm_timeout_ms) || 5000
      max_tokens = get_config(:llm_max_tokens) || 250

      task =
        Task.async(fn ->
          do_chat_completion(messages, callback, api_key, base_url, model, timeout, max_tokens)
        end)

      {:ok, task}
    end
  end

  defp do_chat_completion(messages, callback, api_key, base_url, model, timeout, max_tokens) do
    url = "#{base_url}/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        model: model,
        messages: messages,
        max_tokens: max_tokens,
        stream: true,
        stream_options: %{include_usage: true}
      })

    case make_request(url, headers, body, timeout, callback) do
      {:ok, stats} ->
        callback.({:done, stats})
        :ok

      {:error, reason} ->
        callback.({:error, reason})
    end
  end

  defp make_request(url, headers, body, timeout, callback) do
    uri = URI.parse(url)

    with {:ok, conn} <- connect(uri, timeout),
         {:ok, conn, request_ref} <-
           Mint.HTTP.request(conn, "POST", request_path(uri), headers, body),
         {:ok, status, response_body, stats, final_conn} <-
           receive_response(conn, request_ref, timeout, callback) do
      Mint.HTTP.close(final_conn)

      cond do
        status in 200..299 and stats != nil ->
          {:ok, stats}

        status in 200..299 ->
          with {:ok, response_text, fallback_stats} <- parse_response(status, response_body) do
            callback.({:chunk, response_text})
            {:ok, fallback_stats}
          end

        true ->
          parse_response(status, response_body)
      end
    else
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
      {:ok, conn} -> {:ok, conn}
      {:error, conn, reason} -> {:error, conn, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_path(uri) do
    path = if is_binary(uri.path) and uri.path != "", do: uri.path, else: "/"

    if is_binary(uri.query) and uri.query != "" do
      path <> "?" <> uri.query
    else
      path
    end
  end

  defp receive_response(conn, request_ref, timeout, callback) do
    receive_response(conn, request_ref, timeout, callback, nil, [], false, "", nil, [], false)
  end

  defp receive_response(
         conn,
         request_ref,
         timeout,
         callback,
         status,
         body_parts,
         done?,
         sse_buffer,
         usage,
         streamed_chunks,
         stream_active?
       ) do
    if done? do
      completion_text = IO.iodata_to_binary(Enum.reverse(streamed_chunks))

      stats =
        if stream_active? do
          usage_stats_from_usage_or_text(usage, completion_text)
        else
          nil
        end

      {:ok, status, IO.iodata_to_binary(Enum.reverse(body_parts)), stats, conn}
    else
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            :unknown ->
              receive_response(
                conn,
                request_ref,
                timeout,
                callback,
                status,
                body_parts,
                done?,
                sse_buffer,
                usage,
                streamed_chunks,
                stream_active?
              )

            {:ok, new_conn, responses} ->
              {new_status, new_body_parts, new_done?, new_sse_buffer, new_usage,
               new_streamed_chunks,
               new_stream_active?} =
                Enum.reduce(
                  responses,
                  {status, body_parts, done?, sse_buffer, usage, streamed_chunks, stream_active?},
                  fn response,
                     {acc_status, acc_body, acc_done, acc_buffer, acc_usage, acc_streamed_chunks,
                      acc_stream_active?} ->
                    case response do
                      {:status, ^request_ref, code} ->
                        {
                          code,
                          acc_body,
                          acc_done,
                          acc_buffer,
                          acc_usage,
                          acc_streamed_chunks,
                          acc_stream_active?
                        }

                      {:data, ^request_ref, chunk} ->
                        new_body = [chunk | acc_body]

                        if acc_status in 200..299 do
                          {buffer, maybe_usage, chunks, now_streaming?} =
                            parse_sse_chunk(acc_buffer <> chunk, callback)

                          {
                            acc_status,
                            new_body,
                            acc_done,
                            buffer,
                            merge_usage(acc_usage, maybe_usage),
                            Enum.reverse(chunks) ++ acc_streamed_chunks,
                            acc_stream_active? or now_streaming?
                          }
                        else
                          {
                            acc_status,
                            new_body,
                            acc_done,
                            acc_buffer,
                            acc_usage,
                            acc_streamed_chunks,
                            acc_stream_active?
                          }
                        end

                      {:done, ^request_ref} ->
                        {
                          acc_status,
                          acc_body,
                          true,
                          acc_buffer,
                          acc_usage,
                          acc_streamed_chunks,
                          acc_stream_active?
                        }

                      _ ->
                        {
                          acc_status,
                          acc_body,
                          acc_done,
                          acc_buffer,
                          acc_usage,
                          acc_streamed_chunks,
                          acc_stream_active?
                        }
                    end
                  end
                )

              receive_response(
                new_conn,
                request_ref,
                timeout,
                callback,
                new_status,
                new_body_parts,
                new_done?,
                new_sse_buffer,
                new_usage,
                new_streamed_chunks,
                new_stream_active?
              )

            {:error, error_conn, reason, _responses} ->
              Mint.HTTP.close(error_conn)
              {:error, {:network_error, reason}}
          end
      after
        timeout ->
          Mint.HTTP.close(conn)
          {:error, :timeout}
      end
    end
  end

  defp parse_response(status, body) when status in 200..299 do
    case Jason.decode(body) do
      {:ok, response} ->
        with {:ok, content} <- extract_content(response) do
          {:ok, content, usage_stats(response, content)}
        end

      {:error, reason} ->
        Logger.warning("Failed to parse LLM response: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_response(status, _body), do: {:error, {:http_error, status, nil}}

  defp parse_sse_chunk(payload, callback) do
    case String.split(payload, "\n\n") do
      [single] ->
        {single, nil, [], false}

      segments ->
        rest = List.last(segments) || ""
        complete_segments = Enum.drop(segments, -1)

        Enum.reduce(complete_segments, {rest, nil, [], false}, fn segment,
                                                                  {acc_rest, acc_usage,
                                                                   acc_chunks,
                                                                   acc_stream_active?} ->
          {event_type, maybe_chunk, maybe_usage} = parse_sse_event(segment)

          if is_binary(maybe_chunk) and maybe_chunk != "" do
            callback.({:chunk, maybe_chunk})
          end

          {
            acc_rest,
            merge_usage(acc_usage, maybe_usage),
            if(is_binary(maybe_chunk) and maybe_chunk != "",
              do: [maybe_chunk | acc_chunks],
              else: acc_chunks
            ),
            acc_stream_active? or event_type == :sse
          }
        end)
    end
  end

  defp parse_sse_event(segment) do
    data_lines =
      segment
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(fn line ->
        line
        |> String.replace_prefix("data:", "")
        |> String.trim_leading()
      end)

    data = Enum.join(data_lines, "\n")

    cond do
      data == "" ->
        {:none, nil, nil}

      data == "[DONE]" ->
        {:sse, nil, nil}

      true ->
        case Jason.decode(data) do
          {:ok, response} ->
            {extract_stream_delta(response), Map.get(response, "usage")}
            |> then(fn {chunk, usage} -> {:sse, chunk, usage} end)

          {:error, _} ->
            {:none, nil, nil}
        end
    end
  end

  defp extract_stream_delta(%{"choices" => [%{"delta" => %{"content" => content}} | _]})
       when is_binary(content),
       do: content

  defp extract_stream_delta(_), do: nil

  defp merge_usage(nil, usage), do: usage
  defp merge_usage(usage, nil), do: usage

  defp merge_usage(old, new) do
    Map.merge(old, new, fn _key, old_value, new_value ->
      if is_nil(new_value), do: old_value, else: new_value
    end)
  end

  defp usage_stats_from_usage_or_text(nil, content), do: usage_stats(%{}, content)

  defp usage_stats_from_usage_or_text(usage, content) do
    usage_stats(%{"usage" => usage}, content)
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content),
       do: {:ok, content}

  defp extract_content(%{"choices" => [%{"message" => %{"content" => parts}} | _]})
       when is_list(parts) do
    text =
      parts
      |> Enum.map(fn
        %{"type" => "text", "text" => value} when is_binary(value) -> value
        _ -> ""
      end)
      |> Enum.join("")

    {:ok, text}
  end

  defp extract_content(_response), do: {:error, :invalid_response_format}

  defp usage_stats(response, content) do
    usage = Map.get(response, "usage", %{})
    prompt_tokens = Map.get(usage, "prompt_tokens") || estimate_tokens(content)
    completion_tokens = Map.get(usage, "completion_tokens") || estimate_tokens(content)

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: Map.get(usage, "total_tokens") || prompt_tokens + completion_tokens
    }
  end

  defp estimate_tokens(text) when is_binary(text) do
    ceil(String.length(text) / 4)
  end

  defp scheme_to_atom("https"), do: :https
  defp scheme_to_atom("http"), do: :http
  defp scheme_to_atom(_), do: nil

  defp get_config(key) do
    Application.get_env(:lex, key)
  end
end
