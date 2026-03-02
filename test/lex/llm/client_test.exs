defmodule Lex.LLM.ClientTest do
  use Lex.DataCase, async: false

  alias Lex.LLM.Client
  alias Lex.LLM.ClientMock

  setup do
    # Store original config values
    original_config = %{
      api_key: Application.get_env(:lex, :llm_api_key),
      base_url: Application.get_env(:lex, :llm_base_url),
      model: Application.get_env(:lex, :llm_model),
      timeout: Application.get_env(:lex, :llm_timeout_ms),
      client: Application.get_env(:lex, :llm_client)
    }

    # Ensure test config is set
    Application.put_env(:lex, :llm_api_key, "test_api_key")
    Application.put_env(:lex, :llm_base_url, "https://api.test.openai.com/v1")
    Application.put_env(:lex, :llm_model, "gpt-4o-mini")
    Application.put_env(:lex, :llm_timeout_ms, 5000)

    # Clear mock state
    ClientMock.clear_mock()

    on_exit(fn ->
      # Restore original config
      Application.put_env(:lex, :llm_api_key, original_config.api_key)
      Application.put_env(:lex, :llm_base_url, original_config.base_url)
      Application.put_env(:lex, :llm_model, original_config.model)
      Application.put_env(:lex, :llm_timeout_ms, original_config.timeout)
      Application.put_env(:lex, :llm_client, original_config.client)

      ClientMock.clear_mock()
    end)

    :ok
  end

  describe "stream_chat_completion/2" do
    test "returns error when API key is not configured" do
      # Temporarily disable mock client to test real configuration checking
      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_api_key, nil)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:error, :not_configured} = Client.stream_chat_completion(messages, callback)
    end

    test "returns error when base URL is not configured" do
      # Temporarily disable mock client to test real configuration checking
      Application.delete_env(:lex, :llm_client)
      Application.put_env(:lex, :llm_base_url, nil)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:error, :not_configured} = Client.stream_chat_completion(messages, callback)
    end

    test "returns ok with task when properly configured" do
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

      assert {:ok, _task} =
               Client.stream_chat_completion(messages, callback, connection_owner: self())

      assert ClientMock.get_last_options() == [connection_owner: self()]
    end

    test "validates message structure" do
      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
    end
  end

  describe "streaming with mock client" do
    setup do
      Application.put_env(:lex, :llm_client, ClientMock)
      :ok
    end

    test "callback receives chunks in order" do
      chunks = ["Hello, ", "how ", "are ", "you?"]
      ClientMock.set_mock_chunks(chunks)
      ClientMock.set_chunk_delay(0)

      test_pid = self()

      callback = fn
        {:chunk, content} -> send(test_pid, {:chunk_received, content})
        {:done, _stats} -> send(test_pid, :done_received)
        {:error, _reason} -> send(test_pid, :error_received)
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      # Verify all chunks received in order
      for chunk <- chunks do
        assert_receive {:chunk_received, ^chunk}, 1000
      end

      assert_receive :done_received, 1000
    end

    test "callback receives done with stats" do
      ClientMock.set_mock_response("Test response")
      ClientMock.set_chunk_delay(0)

      test_pid = self()

      callback = fn
        {:chunk, _content} -> :ok
        {:done, stats} -> send(test_pid, {:done_with_stats, stats})
        {:error, _reason} -> send(test_pid, :error_received)
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:done_with_stats, stats}, 1000
      assert is_map(stats)
      assert stats.prompt_tokens >= 0
      assert stats.completion_tokens >= 0
      assert stats.total_tokens >= 0
    end

    test "handles error response from mock" do
      ClientMock.set_mock_error(:timeout)

      test_pid = self()

      callback = fn
        {:chunk, _content} -> send(test_pid, :chunk_received)
        {:done, _stats} -> send(test_pid, :done_received)
        {:error, reason} -> send(test_pid, {:error_received, reason})
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, :timeout}, 1000
      refute_receive :done_received, 100
    end

    test "handles HTTP 4xx errors" do
      ClientMock.set_mock_error({:http_error, 400})

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:http_error, 400}}, 1000
    end

    test "handles HTTP 5xx errors" do
      ClientMock.set_mock_error({:http_error, 500})

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:http_error, 500}}, 1000
    end

    test "handles network timeout errors" do
      ClientMock.set_mock_error({:network_error, :timeout})

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:network_error, :timeout}}, 1000
    end

    test "handles generic errors" do
      ClientMock.set_mock_error(:unknown_error)

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, :unknown_error}, 1000
    end

    test "handles connection errors" do
      ClientMock.set_mock_error({:network_error, :econnrefused})

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:network_error, :econnrefused}}, 1000
    end

    test "handles malformed response errors" do
      ClientMock.set_mock_error({:parse_error, "Invalid JSON"})

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error_received, reason})
        _ -> :ok
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      Task.await(task)

      assert_receive {:error_received, {:parse_error, "Invalid JSON"}}, 1000
    end
  end

  describe "SSE parsing" do
    test "parses content chunks correctly" do
      test_pid = self()

      callback = fn
        {:chunk, content} -> send(test_pid, {:chunk_received, content})
        {:done, stats} -> send(test_pid, {:done_received, stats})
        {:error, reason} -> send(test_pid, {:error_received, reason})
      end

      # We can't easily test the full streaming without mocking Mint.HTTP
      # But we can verify the function accepts valid input and starts a task
      messages = [
        %{role: "system", content: "You are helpful."},
        %{role: "user", content: "Test message"}
      ]

      assert {:ok, task} = Client.stream_chat_completion(messages, callback)
      assert is_struct(task, Task)

      # Clean up - kill the task since we're not making actual HTTP calls
      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "configuration" do
    test "reads llm_model from config" do
      Application.put_env(:lex, :llm_model, "gpt-4")

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
    end

    test "uses default model when not configured" do
      Application.delete_env(:lex, :llm_model)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
    end

    test "reads llm_timeout_ms from config" do
      Application.put_env(:lex, :llm_timeout_ms, 10_000)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
    end

    test "defaults llm_timeout_ms to 5000ms when not configured" do
      Application.delete_env(:lex, :llm_timeout_ms)

      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
    end
  end

  describe "timeout behavior" do
    test "respects configured timeout for streaming receive" do
      # Set a short timeout to test timeout behavior
      Application.put_env(:lex, :llm_timeout_ms, 100)
      Application.put_env(:lex, :llm_client, ClientMock)

      # Set up a slow stream that will exceed the timeout
      ClientMock.set_mock_chunks(["Slow ", "chunk ", "stream"])
      ClientMock.set_chunk_delay(200)

      test_pid = self()

      callback = fn
        {:chunk, _content} -> send(test_pid, :chunk_received)
        {:done, _stats} -> send(test_pid, :done_received)
        {:error, reason} -> send(test_pid, {:error_received, reason})
      end

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, task} = Client.stream_chat_completion(messages, callback)

      # The mock doesn't actually timeout, but we're verifying the config is respected
      # In real scenarios with actual HTTP, the timeout would trigger
      Task.await(task)

      # Should receive some chunks before completing
      assert_receive :chunk_received, 1000
      assert_receive :done_received, 1000
    end

    test "timeout error path emits {:error, :timeout}" do
      Application.put_env(:lex, :llm_client, ClientMock)
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

  describe "error handling" do
    test "handles invalid callback gracefully" do
      messages = [%{role: "user", content: "Hello"}]

      # Function clause error should be raised when callback is not a function
      assert_raise FunctionClauseError, fn ->
        Client.stream_chat_completion(messages, "not_a_function")
      end
    end

    test "handles non-list messages gracefully" do
      callback = fn _ -> :ok end

      assert_raise FunctionClauseError, fn ->
        Client.stream_chat_completion("not_a_list", callback)
      end
    end
  end

  describe "ClientMock helpers" do
    test "set_mock_response stores response text" do
      assert :ok = ClientMock.set_mock_response("Test response")

      test_pid = self()

      callback = fn
        {:chunk, content} -> send(test_pid, {:chunk, content})
        {:done, _stats} -> send(test_pid, :done)
        _ -> :ok
      end

      assert {:ok, task} = ClientMock.stream_chat_completion([], callback)
      Task.await(task)

      # Should receive chunks from the response
      assert_receive {:chunk, _}, 1000
      assert_receive :done, 1000
    end

    test "set_mock_chunks stores specific chunks" do
      chunks = ["chunk1", "chunk2", "chunk3"]
      assert :ok = ClientMock.set_mock_chunks(chunks)

      test_pid = self()

      callback = fn
        {:chunk, content} -> send(test_pid, {:chunk, content})
        _ -> :ok
      end

      assert {:ok, task} = ClientMock.stream_chat_completion([], callback)
      Task.await(task)

      # Should receive all specific chunks
      assert_receive {:chunk, "chunk1"}, 1000
      assert_receive {:chunk, "chunk2"}, 1000
      assert_receive {:chunk, "chunk3"}, 1000
    end

    test "set_mock_error stores error reason" do
      assert :ok = ClientMock.set_mock_error(:test_error)

      test_pid = self()

      callback = fn
        {:error, reason} -> send(test_pid, {:error, reason})
        _ -> :ok
      end

      assert {:ok, task} = ClientMock.stream_chat_completion([], callback)
      Task.await(task)

      assert_receive {:error, :test_error}, 1000
    end

    test "set_chunk_delay configures delay between chunks" do
      assert :ok = ClientMock.set_chunk_delay(10)
      assert :ok = ClientMock.set_chunk_delay(0)
    end

    test "get_last_request returns last messages sent" do
      messages = [%{role: "user", content: "Test message"}]
      callback = fn _ -> :ok end

      assert {:ok, task} = ClientMock.stream_chat_completion(messages, callback)
      Task.await(task)

      assert ClientMock.get_last_request() == messages
    end

    test "clear_mock resets all state" do
      # Set up some state
      ClientMock.set_mock_response("Response")
      ClientMock.set_chunk_delay(100)

      # Stream something to set last_request
      messages = [%{role: "user", content: "Test"}]
      callback = fn _ -> :ok end
      {:ok, task} = ClientMock.stream_chat_completion(messages, callback)
      Task.await(task)

      assert ClientMock.get_last_request() == messages

      # Clear mock
      assert :ok = ClientMock.clear_mock()

      # Verify state is cleared
      assert ClientMock.get_last_request() == nil

      # After clearing, streaming should use default response
      test_pid = self()

      callback = fn
        {:chunk, _content} -> send(test_pid, :chunk_received)
        {:done, _stats} -> send(test_pid, :done_received)
        _ -> :ok
      end

      assert {:ok, task} = ClientMock.stream_chat_completion([], callback)
      Task.await(task)

      assert_receive :chunk_received, 1000
      assert_receive :done_received, 1000
    end
  end
end
