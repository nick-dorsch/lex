"""Smoke tests for the NLP pipeline."""

import json
import subprocess
import sys
from pathlib import Path

import pytest
from lex_nlp.nlp_pipeline import NLPPipeline


class TestPipelineSmoke:
    """Smoke tests verifying pipeline produces valid JSON structure."""

    @pytest.fixture
    def pipeline(self):
        """Create a pipeline instance for testing."""
        return NLPPipeline(language="es")

    def test_pipeline_basic(self, pipeline):
        """Test pipeline with basic Spanish text produces valid structure."""
        text = "Hola mundo. ¿Cómo estás?"
        result = pipeline.process_to_dict(text)

        # 1. Output has "sentences" key with list value
        assert "sentences" in result
        assert isinstance(result["sentences"], list)

        sentences = result["sentences"]

        # 2. At least 2 sentences (split on period)
        assert len(sentences) >= 2

        # 3. Each sentence has required fields: position, text, char_start, char_end, tokens
        sentence_required_fields = {
            "position",
            "text",
            "char_start",
            "char_end",
            "tokens",
        }
        for sentence in sentences:
            assert set(sentence.keys()) >= sentence_required_fields

        # 4. Sentence positions are 1-indexed and sequential
        positions = [sent["position"] for sent in sentences]
        assert positions == list(range(1, len(sentences) + 1))

        # 5. Each token has required fields: position, surface, normalized_surface,
        #    lemma, pos, is_punctuation, char_start, char_end
        token_required_fields = {
            "position",
            "surface",
            "normalized_surface",
            "lemma",
            "pos",
            "is_punctuation",
            "char_start",
            "char_end",
        }

        for sentence in sentences:
            tokens = sentence["tokens"]
            assert isinstance(tokens, list)
            assert len(tokens) > 0

            for token in tokens:
                assert set(token.keys()) >= token_required_fields

            # 6. Token positions within sentence are 1-indexed and sequential
            token_positions = [t["position"] for t in tokens]
            assert token_positions == list(range(1, len(tokens) + 1))

        # 7. is_punctuation is True for "." and "¿"
        # Check first sentence ends with "."
        first_sent_last_token = sentences[0]["tokens"][-1]
        if first_sent_last_token["surface"] == ".":
            assert first_sent_last_token["is_punctuation"] is True

        # Check second sentence starts with "¿"
        second_sent_first_token = sentences[1]["tokens"][0]
        if second_sent_first_token["surface"] == "¿":
            assert second_sent_first_token["is_punctuation"] is True

        # 8. Character offsets are consistent (non-overlapping, within sentence bounds)
        for sentence in sentences:
            sent_start = sentence["char_start"]
            sent_end = sentence["char_end"]

            # Sentence text should match substring
            assert text[sent_start:sent_end] == sentence["text"]

            prev_end = None
            for token in sentence["tokens"]:
                token_start = token["char_start"]
                token_end = token["char_end"]

                # Token surface should match substring
                assert text[token_start:token_end] == token["surface"]

                # Token should be within sentence bounds
                assert token_start >= sent_start
                assert token_end <= sent_end

                # Tokens should not overlap (assuming spaCy doesn't produce overlaps)
                if prev_end is not None:
                    assert token_start >= prev_end

                prev_end = token_end


class TestCLI:
    """Tests for the CLI interface."""

    def test_cli_with_text_argument(self, tmp_path):
        """Test CLI accepts --text argument and produces valid output."""
        output_file = tmp_path / "output.json"
        text = "El gato come."

        result = subprocess.run(
            [
                sys.executable,
                "lex_nlp.py",
                "--text",
                text,
                "--output",
                str(output_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, f"CLI failed with: {result.stderr}"
        assert output_file.exists()

        data = json.loads(output_file.read_text())
        assert "sentences" in data
        assert len(data["sentences"]) == 1
        assert data["sentences"][0]["text"] == "El gato come."

    def test_cli_text_and_input_mutually_exclusive(self, tmp_path):
        """Test that --text and --input cannot be used together."""
        input_file = tmp_path / "input.txt"
        input_file.write_text("Hola mundo.")
        output_file = tmp_path / "output.json"

        result = subprocess.run(
            [
                sys.executable,
                "lex_nlp.py",
                "--input",
                str(input_file),
                "--text",
                "Direct text",
                "--output",
                str(output_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0
        assert (
            "not allowed with argument" in result.stderr.lower()
            or "mutually exclusive" in result.stderr.lower()
        )

    def test_cli_requires_text_or_input(self, tmp_path):
        """Test that either --text or --input is required."""
        output_file = tmp_path / "output.json"

        result = subprocess.run(
            [
                sys.executable,
                "lex_nlp.py",
                "--output",
                str(output_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0
        assert "required" in result.stderr.lower()

    def test_cli_text_with_multilingual_content(self, tmp_path):
        """Test CLI --text with accented characters and punctuation."""
        output_file = tmp_path / "output.json"
        text = "¿Cómo estás? ¡Muy bien!"

        result = subprocess.run(
            [
                sys.executable,
                "lex_nlp.py",
                "--text",
                text,
                "--output",
                str(output_file),
            ],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, f"CLI failed with: {result.stderr}"

        data = json.loads(output_file.read_text())
        assert "sentences" in data
        assert len(data["sentences"]) == 2

        # Check that punctuation is correctly identified
        first_sentence = data["sentences"][0]
        assert first_sentence["tokens"][0]["surface"] == "¿"
        assert first_sentence["tokens"][0]["is_punctuation"] is True
