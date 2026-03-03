defmodule Lex.LLM.ClientTest do
  use Lex.DataCase, async: false

  alias Lex.LLM.Client
  alias Lex.LLM.ClientMock
  alias Lex.TestLLMCompletionPlug
  alias Lex.TestLLMMalformedPlug
  alias Lex.TestLLMUnauthorizedPlug

  setup do
    original_config = %{
      api_key: Application.get_env(:lex, :llm_api_key),
      base_url: Application.get_env(:lex, :llm_base_url),
      model: Application.get_env(:lex, :llm_model),
      timeout: Application.get_env(:lex, :llm_timeout_ms),
      max_tokens: Application.get_env(:lex, :llm_max_tokens),
      client: Application.get_env(:lex, :llm_client)
    }

    Application.put_env(:lex, :llm_api_key, "test_api_key")
    Application.put_env(:lex, :llm_base_url, "https://api.test.openai.com/v1")
    Application.put_env(:lex, :llm_model, "gpt-4o-mini")
    Application.put_env(:lex, :llm_timeout_ms, 5000)
    Application.put_env(:lex, :llm_max_tokens, 100)

    ClientMock.clear_mock()

    on_exit(fn ->
      Application.put_env(:lex, :llm_api_key, original_config.api_key)
      Application.put_env(:lex, :llm_base_url, original_config.base_url)
      Application.put_env(:lex, :llm_model, original_config.model)
      Application.put_env(:lex, :llm_timeout_ms, original_config.timeout)
      Application.put_env(:lex, :llm_max_tokens, original_config.max_tokens)
      Application.put_env(:lex, :llm_client, original_config.client)

      ClientMock.clear_mock()
    end)

    :ok
  end

  describe "stream_chat_completion/2" do
    test "returns error when API key is not configured" do
      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_api_key, nil)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:error, :not_configured} = Client.stream_chat_completion(messages, callback)
    end

    test "returns error when base URL is not configured" do
      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_base_url, nil)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:error, :not_configured} = Client.stream_chat_completion(messages, callback)
    end

    test "returns task when properly configured" do
      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, task} = Client.stream_chat_completion(messages, callback)
      assert is_struct(task, Task)

      Task.shutdown(task, :brutal_kill)
    end

    test "delegates to mock client when configured" do
      Application.put_env(:lex, :llm_client, ClientMock)
      ClientMock.set_mock_response("Mocked response")

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, _task} = Client.stream_chat_completion(messages, callback)
      assert ClientMock.get_last_request() == messages
    end

    test "passes options through to mock client" do
      Application.put_env(:lex, :llm_client, ClientMock)
      ClientMock.set_mock_response("Mocked response")

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, _task} = Client.stream_chat_completion(messages, callback, trace_id: "abc")
      assert ClientMock.get_last_options() == [trace_id: "abc"]
    end
  end

  describe "mock behavior" do
    setup do
      Application.put_env(:lex, :llm_client, ClientMock)
      :ok
    end

    test "callback receives chunks and done" do
      ClientMock.set_mock_chunks(["Hello, ", "world"])
      ClientMock.set_chunk_delay(0)

      test_pid = self()

      callback = fn
        {:chunk, content} -> send(test_pid, {:chunk_received, content})
        {:done, stats} -> send(test_pid, {:done_received, stats})
        {:error, reason} -> send(test_pid, {:error_received, reason})
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:chunk_received, "Hello, "}, 1000
      assert_receive {:chunk_received, "world"}, 1000
      assert_receive {:done_received, stats}, 1000
      assert stats.total_tokens >= 0
      refute_receive {:error_received, _reason}, 100
    end

    test "callback receives error on failure" do
      ClientMock.set_mock_error(:timeout)

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, :timeout}, 1000
    end
  end

  describe "regular API response handling" do
    test "emits a single chunk and done for successful JSON response" do
      Application.delete_env(:lex, :llm_client)
      port = random_available_port()

      start_supervised!(
        {Plug.Cowboy,
         scheme: :http,
         plug: TestLLMCompletionPlug,
         options: [port: port, protocol_options: [idle_timeout: 5_000]]}
      )

      Application.put_env(:lex, :llm_base_url, "http://127.0.0.1:#{port}")
      Application.put_env(:lex, :llm_timeout_ms, 2_000)

      test_pid = self()

      callback = fn
        {:chunk, content} -> send(test_pid, {:chunk_received, content})
        {:done, stats} -> send(test_pid, {:done_received, stats})
        {:error, reason} -> send(test_pid, {:error_received, reason})
      end

      messages = [%{role: "user", content: "Hola"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:chunk_received, "hola"}, 1000

      assert_receive {:done_received,
                      %{prompt_tokens: 11, completion_tokens: 7, total_tokens: 18}},
                     1000

      refute_receive {:error_received, _reason}, 100
    end

    test "returns http error for non-success status" do
      Application.delete_env(:lex, :llm_client)
      port = random_available_port()

      start_supervised!(
        {Plug.Cowboy,
         scheme: :http,
         plug: TestLLMUnauthorizedPlug,
         options: [port: port, protocol_options: [idle_timeout: 5_000]]}
      )

      Application.put_env(:lex, :llm_base_url, "http://127.0.0.1:#{port}")
      Application.put_env(:lex, :llm_timeout_ms, 2_000)

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hola"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:http_error, 401, nil}}, 1000
    end

    test "returns parse_error when JSON is malformed" do
      Application.delete_env(:lex, :llm_client)
      port = random_available_port()

      start_supervised!(
        {Plug.Cowboy,
         scheme: :http,
         plug: TestLLMMalformedPlug,
         options: [port: port, protocol_options: [idle_timeout: 5_000]]}
      )

      Application.put_env(:lex, :llm_base_url, "http://127.0.0.1:#{port}")
      Application.put_env(:lex, :llm_timeout_ms, 2_000)

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hola"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:parse_error, _reason}}, 1000
    end
  end

  describe "error handling" do
    test "raises for invalid callback" do
      messages = [%{role: "user", content: "Hello"}]

      assert_raise FunctionClauseError, fn ->
        Client.stream_chat_completion(messages, "not_a_function")
      end
    end

    test "raises for non-list messages" do
      callback = fn _ -> :ok end

      assert_raise FunctionClauseError, fn ->
        Client.stream_chat_completion("not_a_list", callback)
      end
    end
  end

  defp random_available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
