"""spaCy NLP pipeline for text processing."""

from dataclasses import dataclass, asdict


# Module-level cache for the spaCy model
_nlp = None


def get_nlp(language: str = "es"):
    """Get or initialize the spaCy NLP model (singleton pattern).

    Args:
        language: Language code (default: 'es' for Spanish)

    Returns:
        spaCy Language object
    """
    global _nlp
    if _nlp is None:
        import spacy

        model_name = f"{language}_core_news_md"
        _nlp = spacy.load(model_name)
    return _nlp


@dataclass
class Token:
    """Represents a token with linguistic annotations."""

    position: int  # 1-indexed position within sentence
    surface: str  # original text
    normalized_surface: str  # lowercase
    lemma: str
    pos: str
    is_punctuation: bool
    char_start: int
    char_end: int

    def to_dict(self) -> dict:
        """Convert Token to dictionary for JSON serialization."""
        return asdict(self)


@dataclass
class Sentence:
    """Represents a sentence with tokens."""

    position: int  # 1-indexed position within document
    text: str
    char_start: int
    char_end: int
    tokens: list[Token]

    def to_dict(self) -> dict:
        """Convert Sentence to dictionary for JSON serialization."""
        return {
            "position": self.position,
            "text": self.text,
            "char_start": self.char_start,
            "char_end": self.char_end,
            "tokens": [token.to_dict() for token in self.tokens],
        }


class NLPPipeline:
    """spaCy-based NLP pipeline for sentence segmentation and tokenization."""

    def __init__(self, language: str = "es"):
        """Initialize the NLP pipeline for a specific language.

        Args:
            language: Language code (e.g., 'es' for Spanish)
        """
        self.language = language
        self._nlp = None

    def load(self) -> None:
        """Load the spaCy pipeline for the configured language.

        Downloads the language model if not already cached.
        """
        self._nlp = get_nlp(self.language)

    def process(self, text: str) -> list[Sentence]:
        """Process text and return sentences with tokens.

        Args:
            text: Input text to process

        Returns:
            List of Sentence objects with tokenized and annotated content
        """
        if self._nlp is None:
            self.load()

        assert self._nlp is not None
        doc = self._nlp(text)
        return self._convert_to_sentences(doc)

    def _convert_to_sentences(self, doc) -> list[Sentence]:
        """Convert spaCy document to list of Sentence objects.

        Args:
            doc: spaCy Doc object

        Returns:
            List of Sentence objects
        """
        sentences = []
        for sent_idx, sent_span in enumerate(doc.sents, start=1):
            tokens = []
            for token_idx, token in enumerate(sent_span, start=1):
                token_obj = Token(
                    position=token_idx,
                    surface=token.text,
                    normalized_surface=token.text.lower(),
                    lemma=token.lemma_,
                    pos=token.pos_,
                    is_punctuation=token.is_punct,
                    char_start=token.idx,
                    char_end=token.idx + len(token),
                )
                tokens.append(token_obj)

            sentence_obj = Sentence(
                position=sent_idx,
                text=sent_span.text,
                char_start=sent_span.start_char,
                char_end=sent_span.end_char,
                tokens=tokens,
            )
            sentences.append(sentence_obj)

        return sentences

    def process_to_dict(self, text: str) -> dict:
        """Process text and return JSON-serializable dictionary.

        Args:
            text: Input text to process

        Returns:
            Dictionary with sentences list
        """
        sentences = self.process(text)
        return {"sentences": [sentence.to_dict() for sentence in sentences]}
