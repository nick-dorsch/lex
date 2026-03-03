defmodule Lex.Library.ImportTracker do
  @moduledoc """
  Tracks the state of async import jobs for EPUB files.

  Uses an Agent to maintain state and broadcasts updates via PubSub.

  ## States
    - `:not_started` - Initial state
    - `{:importing, pid}` - Import in progress
    - `{:completed, document_id}` - Successfully imported
    - `{:error, reason}` - Import failed
  """

  use Agent

  alias Phoenix.PubSub

  @type import_status ::
          :not_started
          | {:importing, pid()}
          | {:completed, integer()}
          | {:error, String.t()}

  @type state :: %{String.t() => import_status()}

  # PubSub topic prefix
  @topic_prefix "library_imports"

  @doc """
  Starts the ImportTracker agent.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Starts an import for a file. Returns `:ok` if started, `:already_importing` if already in progress.
  Also broadcasts `{:import_started, file_path, user_id}` via PubSub.
  """
  @spec start_import(String.t(), integer()) :: :ok | :already_importing
  def start_import(file_path, user_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, file_path) do
        {:importing, _pid} ->
          {:already_importing, state}

        _other ->
          pid = self()
          new_state = Map.put(state, file_path, {:importing, pid})
          broadcast(user_id, {:import_started, file_path, user_id})
          {:ok, new_state}
      end
    end)
  end

  @doc """
  Marks an import as completed. Broadcasts `{:import_completed, file_path, document_id, user_id}` via PubSub.
  """
  @spec complete_import(String.t(), integer(), integer()) :: :ok
  def complete_import(file_path, document_id, user_id) do
    Agent.update(__MODULE__, fn state ->
      new_state = Map.put(state, file_path, {:completed, document_id})
      broadcast(user_id, {:import_completed, file_path, document_id, user_id})
      new_state
    end)
  end

  @doc """
  Marks an import as failed. Broadcasts `{:import_failed, file_path, reason, user_id}` via PubSub.
  """
  @spec fail_import(String.t(), String.t(), integer()) :: :ok
  def fail_import(file_path, reason, user_id) do
    Agent.update(__MODULE__, fn state ->
      new_state = Map.put(state, file_path, {:error, reason})
      broadcast(user_id, {:import_failed, file_path, reason, user_id})
      new_state
    end)
  end

  @doc """
  Broadcasts import progress updates for an in-flight import.

  Emits `{:import_progress, file_path, percent, stage, user_id}` via PubSub.
  This does not modify import status state.
  """
  @spec update_progress(String.t(), integer(), String.t(), integer()) :: :ok
  def update_progress(file_path, percent, stage, user_id) do
    broadcast(user_id, {:import_progress, file_path, percent, stage, user_id})
    :ok
  end

  @doc """
  Gets the current status for a file.
  Returns `:not_started` if the file has not been tracked yet.
  """
  @spec get_status(String.t()) :: import_status()
  def get_status(file_path) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state, file_path, :not_started)
    end)
  end

  @doc """
  Resets the status for a file to `:not_started`.
  This is useful for retrying failed imports.
  """
  @spec reset_status(String.t()) :: :ok
  def reset_status(file_path) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, file_path, :not_started)
    end)
  end

  @doc """
  Returns the topic string for a given user_id.
  Used for subscribing to PubSub updates.
  """
  @spec topic(integer()) :: String.t()
  def topic(user_id) do
    "#{@topic_prefix}:#{user_id}"
  end

  # Private function to broadcast messages via PubSub
  defp broadcast(user_id, message) do
    PubSub.broadcast(Lex.PubSub, topic(user_id), message)
  end
end
