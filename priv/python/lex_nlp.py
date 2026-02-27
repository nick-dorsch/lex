#!/usr/bin/env python3
"""CLI entry point for Lex NLP pipeline."""

import argparse
import json
import sys
import traceback
from pathlib import Path

from lex_nlp.nlp_pipeline import NLPPipeline


def main() -> int:
    """Main CLI entry point.

    Returns:
        Exit code (0 for success, 1 for error)
    """
    parser = argparse.ArgumentParser(description="Lex NLP pipeline for text processing")
    parser.add_argument(
        "--input",
        required=True,
        help="Path to UTF-8 text file",
    )
    parser.add_argument(
        "--language",
        default="es",
        help="Language code (default: 'es', currently only Spanish supported)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to write JSON output",
    )

    args = parser.parse_args()

    # Validate input file exists
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: Input file not found: {args.input}", file=sys.stderr)
        return 1

    # Read input file (UTF-8)
    try:
        text = input_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"Error reading input file: {e}", file=sys.stderr)
        return 1

    # Empty text is valid - return empty sentences array
    if not text.strip():
        result = {"sentences": []}
        try:
            output_path = Path(args.output)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Error writing output file: {e}", file=sys.stderr)
            return 1
        return 0

    # Initialize and run pipeline
    try:
        pipeline = NLPPipeline(language=args.language)
        pipeline.load()
    except OSError as e:
        # Model not installed
        model_name = f"{args.language}_core_news_md"
        print(
            f"Error: spaCy model '{model_name}' not installed.\n"
            f"Run: python -m spacy download {model_name}",
            file=sys.stderr,
        )
        return 1
    except Exception as e:
        print(f"Error initializing NLP pipeline: {e}", file=sys.stderr)
        return 1

    # Process text
    try:
        result = pipeline.process_to_dict(text)
    except Exception as e:
        print(f"Error processing text: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return 1

    # Write JSON output
    try:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"Error writing output file: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
