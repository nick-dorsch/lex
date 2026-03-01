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

    try do
      # Write text to input file
      File.write!(input_file, text, [:utf8])

      # Build command
      args = build_args(input_file, output_file, opts)

      # Execute Python script
      case System.cmd("python", args, stderr_to_stdout: true, timeout: @timeout) do
        {_, {_, :timeout}} ->
          {:error, :timeout}

        {output, exit_code} when exit_code != 0 ->
          {:error, {:python_exit, exit_code, output}}

        {_output, 0} ->
          parse_output(output_file)
      end
    rescue
      e in ErlangError ->
        if e.original == :enoent do
          {:error, :python_not_found}
        else
          reraise e, __STACKTRACE__
        end
    after
      # Cleanup temp files
      File.rm(input_file)
      File.rm(output_file)
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
