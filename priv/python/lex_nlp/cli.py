#!/usr/bin/env python3
"""CLI entry point for Lex NLP pipeline."""

import argparse
import sys
from pathlib import Path


def main() -> int:
    """Main CLI entry point.

    Returns:
        Exit code (0 for success, 1 for error)
    """
    parser = argparse.ArgumentParser(description="Lex NLP pipeline for text processing")
    parser.add_argument("--input", required=True, help="Path to input EPUB file")
    parser.add_argument(
        "--language",
        required=True,
        help="Language code for NLP processing (e.g., 'es' for Spanish)",
    )
    parser.add_argument(
        "--output", required=True, help="Path to output directory for processed data"
    )

    args = parser.parse_args()

    # Validate input file exists
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: Input file not found: {args.input}", file=sys.stderr)
        return 1

    # Validate output directory or create it
    output_path = Path(args.output)
    output_path.mkdir(parents=True, exist_ok=True)

    # Placeholder output message
    print(f"Processing {args.input} with language {args.language}")
    print(f"Output will be written to {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
