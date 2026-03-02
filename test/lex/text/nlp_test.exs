defmodule Lex.Text.NLPTest do
  use Lex.DataCase, async: true

  alias Lex.Text.NLP

  describe "process_text/2" do
    test "successfully processes text and returns sentences with tokens" do
      text = "Hola mundo."

      expected_output = %{
        "sentences" => [
          %{
            "position" => 1,
            "text" => "Hola mundo.",
            "char_start" => 0,
            "char_end" => 11,
            "tokens" => [
              %{
                "position" => 1,
                "surface" => "Hola",
                "normalized_surface" => "hola",
                "lemma" => "hola",
                "pos" => "NOUN",
                "is_punctuation" => false,
                "char_start" => 0,
                "char_end" => 4
              },
              %{
                "position" => 2,
                "surface" => "mundo",
                "normalized_surface" => "mundo",
                "lemma" => "mundo",
                "pos" => "NOUN",
                "is_punctuation" => false,
                "char_start" => 5,
                "char_end" => 10
              },
              %{
                "position" => 3,
                "surface" => ".",
                "normalized_surface" => ".",
                "lemma" => ".",
                "pos" => "PUNCT",
                "is_punctuation" => true,
                "char_start" => 10,
                "char_end" => 11
              }
            ]
          }
        ]
      }

      # Mock System.cmd to return success
      parent = self()

      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn cmd, args, opts ->
        send(parent, {:cmd_called, cmd, args, opts})

        # Write the expected output to the output file
        output_path = extract_output_path(args)
        File.write!(output_path, Jason.encode!(expected_output))

        {"", 0}
      end)

      try do
        assert {:ok, sentences} = NLP.process_text(text)
        assert length(sentences) == 1

        sentence = hd(sentences)
        assert sentence["position"] == 1
        assert sentence["text"] == "Hola mundo."
        assert length(sentence["tokens"]) == 3

        # Verify command was called
        assert_receive {:cmd_called, "python", args, opts}
        assert "priv/python/lex_nlp.py" in args
        assert opts[:stderr_to_stdout] == true
      after
        :meck.unload(System)
      end
    end

    test "returns error when python is not found" do
      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn _, _, _ ->
        raise ErlangError, original: :enoent
      end)

      try do
        assert {:error, :python_not_found} = NLP.process_text("Hola")
      after
        :meck.unload(System)
      end
    end

    test "returns error when python exits with non-zero code" do
      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn _, _, _ ->
        {"Error: Model not found", 1}
      end)

      try do
        assert {:error, {:python_exit, 1, _}} = NLP.process_text("Hola")
      after
        :meck.unload(System)
      end
    end

    test "returns error on timeout" do
      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn _, _, _ ->
        Process.sleep(50)
        {"", 0}
      end)

      try do
        assert {:error, :timeout} = NLP.process_text("Hola", timeout: 1)
      after
        :meck.unload(System)
      end
    end

    test "returns error on invalid JSON" do
      parent = self()

      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn cmd, args, _opts ->
        send(parent, {:cmd_called, cmd, args})

        output_path = extract_output_path(args)
        File.write!(output_path, "invalid json")

        {"", 0}
      end)

      try do
        assert {:error, {:invalid_json, _}} = NLP.process_text("Hola")
      after
        :meck.unload(System)
      end
    end

    test "cleans up temp files even on failure" do
      temp_dir = System.tmp_dir!()
      input_pattern = Path.join(temp_dir, "lex_nlp_input_*.txt")

      # Count files before
      before_count = length(Path.wildcard(input_pattern))

      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn _, _, _ ->
        raise ErlangError, original: :enoent
      end)

      try do
        NLP.process_text("Hola")
      catch
        _ -> :ok
      after
        :meck.unload(System)
      end

      # Count files after
      after_count = length(Path.wildcard(input_pattern))

      # Files should be cleaned up
      assert after_count == before_count
    end

    test "accepts language option" do
      parent = self()

      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn cmd, args, opts ->
        send(parent, {:cmd_called, cmd, args, opts})

        output_path = extract_output_path(args)
        File.write!(output_path, ~s({"sentences": []}))

        {"", 0}
      end)

      try do
        NLP.process_text("Hello", language: "en")

        assert_receive {:cmd_called, "python", args, _opts}
        assert "--language" in args
        assert "en" in args
      after
        :meck.unload(System)
      end
    end

    test "preserves UTF-8 input text when writing temp file" do
      parent = self()
      text = "Antoine de Saint-Exupéry dijo: ¡dónde estás!"

      :meck.new(System, [:passthrough])

      :meck.expect(System, :cmd, fn _cmd, args, _opts ->
        input_idx = Enum.find_index(args, &(&1 == "--input"))
        input_path = Enum.at(args, input_idx + 1)

        output_path = extract_output_path(args)
        File.write!(output_path, ~s({"sentences": []}))

        send(parent, {:input_contents, File.read!(input_path)})
        {"", 0}
      end)

      try do
        assert {:ok, []} = NLP.process_text(text)
        assert_receive {:input_contents, input_contents}
        assert input_contents == text
      after
        :meck.unload(System)
      end
    end
  end

  defp extract_output_path(args) do
    idx = Enum.find_index(args, &(&1 == "--output"))
    Enum.at(args, idx + 1)
  end
end
