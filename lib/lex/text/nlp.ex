defmodule Lex.Text.NLP do
  @moduledoc """
  NLP coordination module that interfaces with Python NLP pipeline.
  """

  @python_script "priv/python/lex_nlp.py"
  @timeout 30_000

  @doc """
  Process text through the Python NLP pipeline.

  ## Options
    - `:language` - Language code (default: "es")
    - `:timeout` - Command timeout in milliseconds (default: 30000)

  ## Returns
    - `{:ok, sentences_list}` - List of sentence maps with tokens
    - `{:error, reason}` - Error tuple with descriptive reason
  """
  @spec process_text(String.t(), keyword()) ::
          {:ok, list(map())}
          | {:error, :python_not_found}
          | {:error, {:python_exit, integer(), String.t()}}
          | {:error, {:invalid_json, String.t()}}
          | {:error, :timeout}
  def process_text(text, opts \\ []) do
    temp_dir = System.tmp_dir!()
    input_file = Path.join(temp_dir, "lex_nlp_input_#{unique_id()}.txt")
    output_file = Path.join(temp_dir, "lex_nlp_output_#{unique_id()}.json")
    timeout = Keyword.get(opts, :timeout, @timeout)

    try do
      # Write text to input file
      File.write!(input_file, text)

      # Build command
      args = build_args(input_file, output_file, opts)

      # Execute Python script
      case run_python(args, timeout) do
        {:ok, _output} ->
          parse_output(output_file)

        {:error, reason} ->
          {:error, reason}
      end
    after
      # Cleanup temp files
      File.rm(input_file)
      File.rm(output_file)
    end
  end

  defp run_python(args, timeout) do
    task =
      Task.Supervisor.async_nolink(Lex.Library.ImportTaskSupervisor, fn ->
        System.cmd("python", args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, 0} = result} ->
        {:ok, result}

      {:ok, {output, exit_code}} ->
        {:error, {:python_exit, exit_code, output}}

      {:exit, {%ErlangError{original: :enoent}, _stacktrace}} ->
        {:error, :python_not_found}

      {:exit, reason} ->
        {:error, {:python_exit, 1, Exception.format_exit(reason)}}

      nil ->
        {:error, :timeout}
    end
  end

  defp build_args(input_file, output_file, opts) do
    language = Keyword.get(opts, :language, "es")

    [
      @python_script,
      "--input",
      input_file,
      "--output",
      output_file,
      "--language",
      language
    ]
  end

  defp parse_output(output_file) do
    case File.read(output_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"sentences" => sentences}} ->
            {:ok, sentences}

          {:ok, _} ->
            {:error, {:invalid_json, "missing 'sentences' key"}}

          {:error, reason} ->
            {:error, {:invalid_json, inspect(reason)}}
        end

      {:error, reason} ->
        {:error, {:invalid_json, inspect(reason)}}
    end
  end

  defp unique_id do
    :erlang.unique_integer([:positive])
    |> Integer.to_string()
  end
end
