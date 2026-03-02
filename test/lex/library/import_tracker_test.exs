defmodule Lex.Library.ImportTrackerTest do
  use Lex.DataCase, async: false

  alias Lex.Library.ImportTracker
  alias Phoenix.PubSub

  # Generate unique file paths for each test to avoid state pollution
  defp unique_file_path do
    "/path/to/test_#{System.unique_integer([:positive])}.epub"
  end

  describe "get_status/1" do
    test "returns :not_started for untracked files" do
      assert ImportTracker.get_status("/path/to/unknown.epub") == :not_started
    end

    test "tracks status for multiple files independently" do
      file1 = unique_file_path()
      file2 = unique_file_path()
      user_id = 1

      ImportTracker.start_import(file1, user_id)

      assert match?({:importing, _pid}, ImportTracker.get_status(file1))
      assert ImportTracker.get_status(file2) == :not_started
    end
  end

  describe "start_import/2" do
    test "marks file as importing and returns :ok" do
      file_path = unique_file_path()
      user_id = 1

      assert ImportTracker.start_import(file_path, user_id) == :ok

      status = ImportTracker.get_status(file_path)
      assert match?({:importing, _pid}, status)
    end

    test "returns :already_importing if import already in progress" do
      file_path = unique_file_path()
      user_id = 1

      assert ImportTracker.start_import(file_path, user_id) == :ok
      assert ImportTracker.start_import(file_path, user_id) == :already_importing
    end

    test "allows restart after completion" do
      file_path = unique_file_path()
      user_id = 1

      # First import
      ImportTracker.start_import(file_path, user_id)
      ImportTracker.complete_import(file_path, 123, user_id)

      assert {:completed, 123} = ImportTracker.get_status(file_path)

      # Second import should work
      assert ImportTracker.start_import(file_path, user_id) == :ok
      assert match?({:importing, _pid}, ImportTracker.get_status(file_path))
    end

    test "allows restart after failure" do
      file_path = unique_file_path()
      user_id = 1

      # First import fails
      ImportTracker.start_import(file_path, user_id)
      ImportTracker.fail_import(file_path, "Some error", user_id)

      assert {:error, "Some error"} = ImportTracker.get_status(file_path)

      # Retry should work
      assert ImportTracker.start_import(file_path, user_id) == :ok
      assert match?({:importing, _pid}, ImportTracker.get_status(file_path))
    end
  end

  describe "complete_import/3" do
    test "marks file as completed with document_id" do
      file_path = unique_file_path()
      user_id = 1
      document_id = 456

      ImportTracker.start_import(file_path, user_id)
      assert :ok = ImportTracker.complete_import(file_path, document_id, user_id)

      assert {:completed, ^document_id} = ImportTracker.get_status(file_path)
    end
  end

  describe "fail_import/3" do
    test "marks file as failed with reason" do
      file_path = unique_file_path()
      user_id = 1

      ImportTracker.start_import(file_path, user_id)
      assert :ok = ImportTracker.fail_import(file_path, "Parse error", user_id)

      assert {:error, "Parse error"} = ImportTracker.get_status(file_path)
    end
  end

  describe "reset_status/1" do
    test "resets status to :not_started" do
      file_path = unique_file_path()
      user_id = 1

      ImportTracker.start_import(file_path, user_id)
      assert match?({:importing, _pid}, ImportTracker.get_status(file_path))

      ImportTracker.reset_status(file_path)
      assert ImportTracker.get_status(file_path) == :not_started
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts import_started event" do
      file_path = unique_file_path()
      user_id = 42
      topic = ImportTracker.topic(user_id)

      # Subscribe to the topic
      PubSub.subscribe(Lex.PubSub, topic)

      ImportTracker.start_import(file_path, user_id)

      assert_receive {:import_started, ^file_path, ^user_id}, 1000
    end

    test "broadcasts import_completed event" do
      file_path = unique_file_path()
      user_id = 42
      document_id = 123
      topic = ImportTracker.topic(user_id)

      PubSub.subscribe(Lex.PubSub, topic)

      ImportTracker.start_import(file_path, user_id)
      ImportTracker.complete_import(file_path, document_id, user_id)

      assert_receive {:import_completed, ^file_path, ^document_id, ^user_id}, 1000
    end

    test "broadcasts import_failed event" do
      file_path = unique_file_path()
      user_id = 42
      reason = "Some error"
      topic = ImportTracker.topic(user_id)

      PubSub.subscribe(Lex.PubSub, topic)

      ImportTracker.start_import(file_path, user_id)
      ImportTracker.fail_import(file_path, reason, user_id)

      assert_receive {:import_failed, ^file_path, ^reason, ^user_id}, 1000
    end

    test "broadcasts are scoped to user_id" do
      file_path = unique_file_path()
      user_id_1 = System.unique_integer([:positive])
      user_id_2 = System.unique_integer([:positive])

      topic_1 = ImportTracker.topic(user_id_1)
      _topic_2 = ImportTracker.topic(user_id_2)

      PubSub.subscribe(Lex.PubSub, topic_1)

      # Start import for user 2
      ImportTracker.start_import(file_path, user_id_2)

      # Should not receive message for user 1
      refute_receive {:import_started, ^file_path, ^user_id_1}, 100
      refute_receive {:import_started, ^file_path, ^user_id_2}, 100
    end
  end

  describe "concurrent access" do
    test "handles concurrent start_import calls" do
      file_path = unique_file_path()
      user_id = 1

      # Start multiple processes trying to import the same file
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            ImportTracker.start_import(file_path, user_id)
          end)
        end

      results = Task.await_many(tasks)

      # Only one should succeed, rest should get :already_importing
      assert Enum.count(results, &(&1 == :ok)) == 1
      assert Enum.count(results, &(&1 == :already_importing)) == 9
    end

    test "handles concurrent status updates" do
      file_path = unique_file_path()
      user_id = 1

      ImportTracker.start_import(file_path, user_id)

      # Complete and fail concurrently
      tasks = [
        Task.async(fn -> ImportTracker.complete_import(file_path, 1, user_id) end),
        Task.async(fn -> ImportTracker.fail_import(file_path, "error", user_id) end),
        Task.async(fn -> ImportTracker.complete_import(file_path, 2, user_id) end)
      ]

      Task.await_many(tasks)

      # Final status should be one of the updates (last one wins due to Agent semantics)
      status = ImportTracker.get_status(file_path)
      assert match?({:completed, _}, status) or match?({:error, _}, status)
    end
  end

  describe "topic/1" do
    test "returns correct topic format" do
      assert ImportTracker.topic(123) == "library_imports:123"
      assert ImportTracker.topic(0) == "library_imports:0"
    end
  end
end
