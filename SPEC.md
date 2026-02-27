# Lex Specification (Draft v0.1)

## 1. Product Vision

Lex is a focused reading companion for language learners. Users upload ebooks, read
sentence-by-sentence, and build vocabulary through lightweight interaction instead of
flashcard-heavy workflows.

Core experience goals:

- Keep the reading interface calm and distraction-light.
- Make vocabulary state visible at a glance (new, seen, learning, known).
- Support keyboard-first navigation inspired by Vim.
- Turn normal reading progress into vocabulary progress automatically.

## 2. V1 End Goals

MVP language scope is fixed to Spanish learning for English speakers:

- Reading language: `es`
- Explanation/help language: `en`

By the end of V1, a user can:

1. Create an account and upload an EPUB.
2. Wait for processing to complete (chapter split, sentence split, tokenization,
   lemmatization).
3. Open a reader UI and navigate with `j`/`k` between sentences and `w`/`b` between
   words.
4. Mark words as `learning`.
5. Advance through sentences and have non-learning words automatically become `known`.
6. Skip content (frontmatter, irrelevant sections) without promoting skipped words to
   `known`.
7. Trigger LLM help with `space` for sentence-level or focused-word explanations in
   English for MVP.
8. Resume reading where they left off.

## 3. System Architecture

### 3.1 Stack

- Backend and web: Elixir + Phoenix + Ecto
- Database: SQLite (`ecto_sqlite3`)
- NLP pipeline: Python CLI using Stanza
- Frontend interaction: Phoenix LiveView + minimal JS hooks for keyboard and local UI behavior
- Dev task runner: go-task (`Taskfile.yml`)

### 3.2 High-level Flow

1. User uploads EPUB in Phoenix.
2. Elixir stores the file and creates a `document` row with `processing` status.
3. Elixir calls Python CLI with input file path + language.
4. Python parses EPUB into ordered sections (chapters), runs sentence/token/lemma
   analysis, and writes JSON output.
5. Elixir ingests JSON output into SQLite (`document -> section -> sentence -> token`)
   and upserts lexemes.
6. Document status changes to `ready`, and the reader becomes available.

## 4. Domain Model

### 4.1 Core Hierarchy

- `documents`
- `sections` (chapters or logical blocks in reading order)
- `sentences`
- `tokens`
- `lexemes` (lemma-level vocabulary entries)

### 4.2 Schema Proposal

#### `documents`

- `id`
- `user_id`
- `title`
- `author`
- `language` (BCP-47 code, MVP constraint: `es`)
- `status` (`uploaded | processing | ready | failed`)
- `source_file`
- `inserted_at`, `updated_at`

#### `sections`

- `id`
- `document_id`
- `position` (1..N)
- `title`
- `source_href` (EPUB reference when available)
- `inserted_at`, `updated_at`
- Unique: `(document_id, position)`

#### `sentences`

- `id`
- `section_id`
- `position` (1..N within section)
- `text`
- `char_start`, `char_end` (optional)
- `inserted_at`, `updated_at`
- Unique: `(section_id, position)`

#### `lexemes`

- `id`
- `language`
- `lemma`
- `normalized_lemma`
- `pos`
- `inserted_at`, `updated_at`
- Unique: `(language, normalized_lemma, pos)`

#### `tokens`

- `id`
- `sentence_id`
- `position` (1..N within sentence)
- `surface`
- `normalized_surface`
- `lemma`
- `pos`
- `is_punctuation`
- `char_start`, `char_end`
- `lexeme_id` (nullable until linked)
- `inserted_at`, `updated_at`
- Unique: `(sentence_id, position)`

#### `user_lexeme_states`

- `id`
- `user_id`
- `lexeme_id`
- `status` (`seen | learning | known`)
- `seen_count`
- `first_seen_at`
- `last_seen_at`
- `known_at`
- `learning_since`
- `inserted_at`, `updated_at`
- Unique: `(user_id, lexeme_id)`

#### `user_sentence_states`

- `id`
- `user_id`
- `sentence_id`
- `status` (`unread | read`)
- `read_at`
- `inserted_at`, `updated_at`
- Unique: `(user_id, sentence_id)`

#### `reading_positions`

- `id`
- `user_id`
- `document_id`
- `section_id`
- `sentence_id`
- `active_token_position`
- `inserted_at`, `updated_at`
- Unique: `(user_id, document_id)`

#### `llm_help_requests`

- `id`
- `user_id`
- `document_id`
- `sentence_id`
- `token_id` (nullable for sentence-level help)
- `request_type` (`sentence | token`)
- `response_language` (user primary language, MVP constraint: `en`)
- `provider`
- `model`
- `latency_ms`
- `prompt_tokens`, `completion_tokens` (optional)
- `response_text` (or redacted excerpt)
- `inserted_at`

#### `reading_events`

- `id`
- `user_id`
- `document_id`
- `sentence_id` (nullable)
- `token_id` (nullable)
- `event_type` (`enter_sentence | advance_sentence | skip_range | mark_learning | unmark_learning | llm_help_requested`)
- `payload` (JSON)
- `inserted_at`

## 5. Vocabulary and Sentence Progression Rules

### 5.1 Lexeme state model

Base states shown in UI:

- `new`: no row in `user_lexeme_states` for `(user, lexeme)`.
- `seen`: encountered but not mastered.
- `learning`: user explicitly marked for study.
- `known`: treated as learned for reading progression.

Scope rules:

- State is lexeme-scoped (`user_id + lexeme_id`), not token-instance-scoped.
- Repeated tokens in one sentence still map to one lexeme state update.

Transition rules:

1. On first encounter in a sentence, each non-punctuation lexeme with no existing state
   becomes `seen`.
2. Advancing to next sentence (`j`) promotes `seen -> known` for lexemes in the current
   sentence.
3. Lexemes marked `learning` stay `learning` when advancing.
4. `known` never auto-demotes.
5. Going backward (`k`) never changes lexeme state.
6. Skip actions never change lexeme/token state.

### 5.2 Sentence state model

Sentence state is tracked per `(user, sentence)` with `unread | read`.

1. Entering/loading a sentence does not mark it `read`.
2. A sentence becomes `read` only when the user progresses past it via normal next
   action.
3. Skipped sentences remain `unread`.
4. Skip actions do not retroactively mark intermediate sentences as `read`.

## 6. EPUB + NLP Pipeline Contract

### 6.1 Elixir -> Python CLI

Example interface:

```bash
python3 priv/python/lex_nlp.py \
  --input /abs/path/book.epub \
  --language es \
  --output /abs/path/output.json
```

### 6.2 Python responsibilities

- Parse EPUB spine in reading order.
- Split content into sections (chapter-aware where possible).
- Normalize text and strip markup noise.
- Run Stanza sentence segmentation, tokenization, POS, and lemmatization.
- Emit structured JSON with sections/sentences/tokens.

### 6.3 Output shape (simplified)

```json
{
  "title": "Book Title",
  "author": "Author",
  "language": "es",
  "sections": [
    {
      "position": 1,
      "title": "Chapter 1",
      "sentences": [
        {
          "position": 1,
          "text": "Hola mundo.",
          "tokens": [
            {
              "position": 1,
              "surface": "Hola",
              "lemma": "hola",
              "pos": "INTJ",
              "is_punctuation": false
            }
          ]
        }
      ]
    }
  ]
}
```

### 6.4 Elixir ingestion responsibilities

- Validate JSON contract.
- Insert hierarchy in a transaction (`Ecto.Multi`).
- Upsert lexemes and link tokens.
- Store per-document processing metadata and errors.

## 7. Reader UI Spec (V1)

### 7.1 Layout goals

- Single primary sentence in focus.
- Minimal chrome and clear typography.
- Small but visible vocabulary indicators.
- Mobile and desktop parity.

### 7.2 Interaction model

- `j`: next sentence (apply promotion rules)
- `k`: previous sentence
- `w`: next token in sentence
- `b`: previous token in sentence
- `space`: trigger LLM help (sentence or focused token)
- Click token: focus token
- Toggle learning on focused token (button and keyboard shortcut)

### 7.3 Visual language (initial)

- `new`: subtle amber underline
- `seen`: muted dotted underline
- `learning`: blue outline/marker
- `known`: near-default text with tiny green indicator

No large badges or heavy panels in the reading area.

### 7.4 LLM help behavior

- Pressing `space` with no focused token requests sentence explanation in English for
MVP.
- Pressing `space` with a focused token requests word explanation in English for MVP,
using sentence context.
- Each request is stored in `llm_help_requests` with `sentence_id` and optional
`token_id`.
- LLM help is assistive only; it does not directly change lexeme or sentence state.

## 8. Configuration and Secrets

LLM provider settings are runtime-configured from environment variables (`.env` in local
dev):

- `LEX_LLM_PROVIDER` selects provider (for example `openai`).
- `LEX_LLM_MODEL` selects model per provider.
- Provider API key is loaded from env (`LEX_LLM_API_KEY` or provider-specific key).
- Timeouts/token budgets are env-configured to control cost and latency.

The repository includes `.env.example` as the canonical template.

## 9. Elixir Project Structure

Recommended contexts:

- `Lex.Accounts`
- `Lex.Library` (documents, sections, ingestion lifecycle)
- `Lex.Text` (sentences, tokens, lexemes)
- `Lex.Reader` (positions, navigation, state transitions)
- `Lex.Vocab` (user lexeme states and reporting)

Keep controllers/LiveViews thin; put business logic in contexts.

## 10. Best Practices for a New Elixir Codebase

1. Use pattern matching and small pure functions for transformations.
2. Put multi-table writes in `Ecto.Multi` transactions.
3. Avoid business logic in templates/LiveViews/controllers.
4. Model domain rules as explicit context functions (ex: `advance_sentence/3`).
5. Add tests for every vocabulary transition edge case.
6. Prefer explicit structs/maps over loose keyword passing in core logic.

## 11. Dev Workflow with go-task

Initial `Taskfile.yml` targets:

- `task setup` - install deps, create/migrate DB, setup Python venv
- `task dev` - run Phoenix server
- `task test` - run Elixir and Python tests
- `task lint` - format/lint both languages
- `task ingest FILE=... LANG=...` - run manual ingestion pipeline

## 12. Testing Strategy

- Elixir unit tests for contexts and transition rules.
- Elixir integration tests for upload -> process -> read flow.
- Python tests for EPUB parsing and Stanza output contract.
- Browser tests for keyboard navigation and highlights.

Must-have edge cases:

- Skip content does not mark words `known`.
- Advancing sentence promotes non-learning words.
- Repeated tokens in one sentence do not create duplicate state rows.
- Punctuation tokens are ignored for vocab progression.
- Sentence remains unread until progression, and skipped sentences remain unread.
- LLM help requests are logged with correct sentence and token foreign keys.
- Reading events are recorded for enter/advance/skip/learning/LLM-help interactions.

## 13. Milestone Plan

### Milestone 1: Foundation

- Bootstrap Phoenix app with SQLite.
- Add authentication.
- Add base schemas + migrations.

### Milestone 2: NLP ingestion prototype

- Build Python CLI with fixed fixture EPUB.
- Define and validate JSON contract.
- Ingest into DB end-to-end.

### Milestone 3: Reader core

- Build sentence-focused reader UI.
- Implement keyboard navigation.
- Persist reading position.

### Milestone 4: Vocabulary state engine

- Implement transition rules.
- Add learning toggle actions.
- Persist `reading_events` for reader actions.
- Add tests for progression and skip behavior.

### Milestone 5: UX polish + reliability

- Improve visual clarity and mobile behavior.
- Add processing/error feedback for uploads.
- Add LLM help UX flow + persistence and observability.
- Add instrumentation and basic performance checks.

## 14. Non-goals for V1

- Built-in dictionary/translation service.
- Spaced-repetition scheduling.
- Audio sync or TTS.
- Multi-user shared annotations.

## 15. Locked Decisions

- First lexeme encounter defaults to `seen`.
- On normal sentence advance, the previous sentence becomes `read` and non-learning
lexemes in that sentence become `known`.
- Skip actions do not mark skipped sentences as `read`, and do not change token/lexeme
state.
- Vocabulary state is lexeme-scoped (word-level), not token-instance-scoped.
- MVP supports Spanish reading (`es`) for English speakers (`en`).
- `reading_events` is included in MVP.
- LLM provider/model are configured from env.

## 16. Open Decisions to Confirm

1. Whether skip behavior in V1 should support only single-step skipping, section-level
   skipping, or custom range skipping.
2. Whether to cache LLM responses per `(sentence_id, token_id, response_language)`.
3. Retention policy for stored LLM response text (full text vs redacted excerpt only).
