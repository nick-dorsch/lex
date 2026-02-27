"""EPUB parsing module for extracting text content."""

from pathlib import Path


def parse_epub(epub_path: Path) -> list[str]:
    """Parse an EPUB file and extract text content.

    Args:
        epub_path: Path to the EPUB file

    Returns:
        List of text content from each chapter/section

    Raises:
        FileNotFoundError: If EPUB file doesn't exist
        ValueError: If file is not a valid EPUB
    """
    if not epub_path.exists():
        raise FileNotFoundError(f"EPUB file not found: {epub_path}")

    # TODO: Implement EPUB parsing using ebooklib
    # TODO: Extract HTML content from chapters
    # TODO: Strip HTML tags and return plain text

    return []


def extract_metadata(epub_path: Path) -> dict:
    """Extract metadata from an EPUB file.

    Args:
        epub_path: Path to the EPUB file

    Returns:
        Dictionary containing title, author, language, etc.
    """
    if not epub_path.exists():
        raise FileNotFoundError(f"EPUB file not found: {epub_path}")

    # TODO: Implement metadata extraction

    return {}
