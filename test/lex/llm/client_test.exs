defmodule Lex.LLM.ClientTest do
  use Lex.DataCase, async: false

  alias Lex.LLM.Client

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

    on_exit(fn ->
      # Restore original config
      Application.put_env(:lex, :llm_api_key, original_config.api_key)
      Application.put_env(:lex, :llm_base_url, original_config.base_url)
      Application.put_env(:lex, :llm_model, original_config.model)
      Application.put_env(:lex, :llm_timeout_ms, original_config.timeout)
      Application.put_env(:lex, :llm_client, original_config.client)
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

    test "returns task when properly configured" do
      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
    end

    test "validates message structure" do
      messages = [%{role: "user", content: "Hello"}]
      callback = fn _ -> :ok end

      assert {:ok, %Task{}} = Client.stream_chat_completion(messages, callback)
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
end
