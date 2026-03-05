# Lex

Lex is a Phoenix + LiveView reading companion for language learners.

You import books (EPUB), read sentence-by-sentence, and track vocabulary progress.

## Run the Web Server

The two most important commands are:

- Development server: `task dev`
- Production-mode server: `task run` (alias: `task prod`)

Both start the app on `http://localhost:4000` by default.

### 1) First-time setup

Install required tools (recommended via `mise`):

```bash
mise install
```

Install Elixir dependencies and create/migrate the database:

```bash
mix setup
```

Create your local environment file:

```bash
cp .env.example .env
```

Install Python dependencies for the NLP pipeline:

```bash
uv sync --project priv/python
```

Install the Spanish spaCy model used by the importer:

```bash
uv run --project priv/python python -m spacy download es_core_news_md
```

## Development Server

Use this for local development with code reloading and Tailwind watcher:

```bash
task dev
```

Equivalent direct command:

```bash
mix phx.server
```

What it does:

- Runs in `MIX_ENV=dev`
- Uses DB file `priv/repo/lex_dev.db`
- Enables LiveView/code reload (`config/dev.exs`)
- Watches Tailwind changes

Open `http://localhost:4000`.

## Production-Mode Server

Use this to run the app with production config locally or on a server.

### Quick start (Taskfile)

```bash
task run
```

This task:

1. Builds/minifies static assets (`MIX_ENV=prod mix assets.deploy`)
2. Starts Phoenix in prod (`MIX_ENV=prod mix phx.server`)

### Required environment variables

At minimum, set:

- `SECRET_KEY_BASE` (required in prod)

Generate one if needed:

```bash
mix phx.gen.secret
```

Optional but common:

- `PORT` (default: `4000`)
- `HOST` (default: `localhost`)
- `CALIBRE_LIBRARY_PATH` (default: `~/Calibre Library`)
- `LLM_PROVIDER`, `LLM_API_KEY`, `LLM_MODEL`, `LLM_BASE_URL`, `LLM_TIMEOUT_MS`

Production DB location is:

- `~/.lex/lex.db`

Run migrations before first prod start (and after schema changes):

```bash
MIX_ENV=prod mix ecto.migrate
```

### Direct prod commands (without `task`)

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix phx.server
```

## User Guide (Quick)

1. Start server (`task dev` or `task run`)
2. Open `http://localhost:4000`
3. Complete the profile setup modal (name/email/target languages)
4. Ensure your Calibre library path exists (`CALIBRE_LIBRARY_PATH`)
5. Import a book from the Library page and start reading

Notes:

- If `CALIBRE_LIBRARY_PATH` is missing or invalid, the UI will warn and library scans return empty.
- LLM help features require `LLM_API_KEY` and related LLM env vars.

## Developer Guide

### Architecture

- `Lex.Library` - EPUB import, Calibre scan, ingestion pipeline
- `Lex.Reader` - reading position/navigation/events
- `Lex.Vocab` - lexeme state transitions and LLM help request tracking
- `Lex.Text.NLP` - bridge from Elixir to Python CLI (`priv/python/lex_nlp.py`)
- `LexWeb` - router, LiveViews, components, controllers

Main routes:

- `/library` - unified library/import view
- `/read/:document_id` - sentence reader
- `/stats` - progress stats

### Development commands

```bash
# Run all tests
task test

# Elixir tests only
mix test

# Python tests only
uv run --directory priv/python pytest

# Format Elixir
mix format

# Lint/type checks
mix credo
mix dialyzer
```

### Data and config details

- Dev DB: `priv/repo/lex_dev.db`
- Test DB: `priv/repo/lex_test.db`
- Prod DB: `~/.lex/lex.db`
- Runtime config: `config/runtime.exs`
- Dev server config: `config/dev.exs`
- Prod server config: `config/prod.exs`

## Troubleshooting

- `SECRET_KEY_BASE is missing` in prod:
  - Set `SECRET_KEY_BASE` before starting prod server.
- Import fails with Python/model errors:
  - Confirm Python deps are installed in an environment available to `python` on your PATH.
  - Install model: `python -m spacy download es_core_news_md`
- Port already in use:
  - Set a different port, for example: `PORT=4001 task run`
