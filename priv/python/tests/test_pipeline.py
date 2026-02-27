"""Smoke tests for the NLP pipeline."""

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
