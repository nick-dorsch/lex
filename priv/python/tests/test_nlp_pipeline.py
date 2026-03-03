"""Tests for the NLP pipeline."""

import pytest

from lex_nlp.nlp_pipeline import NLPPipeline, Sentence, Token, get_nlp


class TestModelCaching:
    """Test model loading and caching."""

    def test_singleton_pattern(self):
        """Test that model is cached and reused."""
        global _nlp
        # Reset cache for testing
        import lex_nlp.nlp_pipeline as nlp_module

        original_nlp = nlp_module._nlp
        nlp_module._nlp = None

        try:
            # First call should load model
            nlp1 = get_nlp("es")
            assert nlp_module._nlp is not None

            # Second call should return same instance
            nlp2 = get_nlp("es")
            assert nlp1 is nlp2
        finally:
            # Restore original
            nlp_module._nlp = original_nlp


class TestDataClasses:
    """Test Token and Sentence dataclasses."""

    def test_token_creation(self):
        """Test Token dataclass creation."""
        token = Token(
            position=1,
            surface="Hola",
            normalized_surface="hola",
            lemma="hola",
            pos="INTJ",
            is_punctuation=False,
            char_start=0,
            char_end=4,
        )
        assert token.position == 1
        assert token.surface == "Hola"
        assert token.normalized_surface == "hola"
        assert token.lemma == "hola"
        assert token.pos == "INTJ"
        assert token.is_punctuation is False
        assert token.char_start == 0
        assert token.char_end == 4

    def test_sentence_creation(self):
        """Test Sentence dataclass creation."""
        token = Token(
            position=1,
            surface="Hola",
            normalized_surface="hola",
            lemma="hola",
            pos="INTJ",
            is_punctuation=False,
            char_start=0,
            char_end=4,
        )
        sentence = Sentence(
            position=1, text="Hola", char_start=0, char_end=4, tokens=[token]
        )
        assert sentence.position == 1
        assert sentence.text == "Hola"
        assert sentence.char_start == 0
        assert sentence.char_end == 4
        assert len(sentence.tokens) == 1

    def test_token_to_dict(self):
        """Test Token serialization."""
        token = Token(
            position=1,
            surface="Hola",
            normalized_surface="hola",
            lemma="hola",
            pos="INTJ",
            is_punctuation=False,
            char_start=0,
            char_end=4,
        )
        d = token.to_dict()
        assert d["position"] == 1
        assert d["surface"] == "Hola"
        assert d["normalized_surface"] == "hola"
        assert d["lemma"] == "hola"
        assert d["pos"] == "INTJ"
        assert d["is_punctuation"] is False
        assert d["char_start"] == 0
        assert d["char_end"] == 4

    def test_sentence_to_dict(self):
        """Test Sentence serialization."""
        token = Token(
            position=1,
            surface="Hola",
            normalized_surface="hola",
            lemma="hola",
            pos="INTJ",
            is_punctuation=False,
            char_start=0,
            char_end=4,
        )
        sentence = Sentence(
            position=1, text="Hola", char_start=0, char_end=4, tokens=[token]
        )
        d = sentence.to_dict()
        assert d["position"] == 1
        assert d["text"] == "Hola"
        assert d["char_start"] == 0
        assert d["char_end"] == 4
        assert len(d["tokens"]) == 1


class TestNLPPipeline:
    """Test NLPPipeline functionality."""

    @pytest.fixture
    def pipeline(self):
        """Create a pipeline instance for testing."""
        return NLPPipeline(language="es")

    def test_pipeline_initialization(self, pipeline):
        """Test pipeline initialization."""
        assert pipeline.language == "es"
        assert pipeline._nlp is None

    def test_pipeline_load(self, pipeline):
        """Test pipeline loading."""
        pipeline.load()
        assert pipeline._nlp is not None

    def test_process_simple_sentence(self, pipeline):
        """Test processing a simple sentence."""
        text = "Hola mundo."
        sentences = pipeline.process(text)

        assert len(sentences) == 1
        sentence = sentences[0]
        assert sentence.position == 1
        assert sentence.text == "Hola mundo."
        assert sentence.char_start == 0
        assert sentence.char_end == len(text)

        # Check tokens
        assert len(sentence.tokens) > 0

        # Check first token
        first_token = sentence.tokens[0]
        assert first_token.position == 1
        assert first_token.surface == "Hola"
        assert first_token.normalized_surface == "hola"
        assert first_token.char_start == 0
        assert first_token.char_end == 4
        assert first_token.is_punctuation is False

    def test_process_multiple_sentences(self, pipeline):
        """Test processing multiple sentences."""
        text = "Hola mundo. ¿Cómo estás?"
        sentences = pipeline.process(text)

        assert len(sentences) == 2

        # First sentence
        assert sentences[0].position == 1
        assert sentences[0].text == "Hola mundo."

        # Second sentence
        assert sentences[1].position == 2
        assert sentences[1].text == "¿Cómo estás?"

    def test_process_splits_on_blank_lines(self, pipeline):
        """Test that blank lines create sentence boundaries."""
        text = "Capítulo 1\n\nHabía una vez."
        sentences = pipeline.process(text)

        assert len(sentences) == 2

        assert sentences[0].position == 1
        assert sentences[0].text == "Capítulo 1"
        assert text[sentences[0].char_start : sentences[0].char_end] == "Capítulo 1"

        assert sentences[1].position == 2
        assert sentences[1].text == "Había una vez."
        assert text[sentences[1].char_start : sentences[1].char_end] == "Había una vez."

    def test_token_positions_are_one_indexed(self, pipeline):
        """Test that token positions start at 1, not 0."""
        text = "El gato come."
        sentences = pipeline.process(text)

        for sentence in sentences:
            positions = [token.position for token in sentence.tokens]
            assert all(p >= 1 for p in positions)
            assert positions == list(range(1, len(positions) + 1))

    def test_sentence_positions_are_one_indexed(self, pipeline):
        """Test that sentence positions start at 1, not 0."""
        text = "Primera. Segunda."
        sentences = pipeline.process(text)

        positions = [sent.position for sent in sentences]
        assert positions == [1, 2]

    def test_punctuation_detection(self, pipeline):
        """Test punctuation detection."""
        text = "Hola mundo."
        sentences = pipeline.process(text)

        tokens = sentences[0].tokens
        # Last token should be punctuation
        last_token = tokens[-1]
        assert last_token.surface == "."
        assert last_token.is_punctuation is True

        # First token should not be punctuation
        first_token = tokens[0]
        assert first_token.is_punctuation is False

    def test_character_offsets(self, pipeline):
        """Test character offsets are accurate."""
        text = "El gato come."
        sentences = pipeline.process(text)

        for sentence in sentences:
            # Sentence offsets
            assert text[sentence.char_start : sentence.char_end] == sentence.text

            # Token offsets
            for token in sentence.tokens:
                assert text[token.char_start : token.char_end] == token.surface

    def test_process_to_dict(self, pipeline):
        """Test process_to_dict returns JSON-serializable output."""
        import json

        text = "Hola mundo."
        result = pipeline.process_to_dict(text)

        # Should be serializable
        json_str = json.dumps(result)
        assert isinstance(json_str, str)

        # Verify structure
        assert "sentences" in result
        assert len(result["sentences"]) == 1
        assert "tokens" in result["sentences"][0]

    def test_lemmatization(self, pipeline):
        """Test that lemmatization produces lemmas."""
        text = "Los gatos comen pescado."
        sentences = pipeline.process(text)

        for sentence in sentences:
            for token in sentence.tokens:
                assert token.lemma is not None
                assert len(token.lemma) > 0

    def test_pos_tags(self, pipeline):
        """Test that POS tags are assigned."""
        text = "Hola mundo."
        sentences = pipeline.process(text)

        for sentence in sentences:
            for token in sentence.tokens:
                assert token.pos is not None
                assert len(token.pos) > 0
