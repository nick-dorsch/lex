# Lex

Lex is a Phoenix + LiveView reading companion for language learners.

You import books (EPUB), read sentence-by-sentence, and track vocabulary progress.

## Run the Web Server

The two most important commands are:

- Development server: `mise run dev`
- Production-mode server: `mise run prod`

Both start the app on `http://localhost:4000` by default.

### 1) First-time setup

Install required tools:

```bash
mise install && mise run setup
```

This one-liner installs tool versions and runs first-time setup (Elixir deps, DB setup,
`.env` bootstrap if missing, Python deps, and spaCy model check/download).

All `mise run ...` tasks automatically load environment variables from `.env`.

## Development Server

Use this for local development with code reloading and Tailwind watcher:

```bash
mise run dev
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

### Quick start (mise task)

```bash
mise run prod
```

This task:

1. Builds/minifies static assets (`MIX_ENV=prod mix assets.deploy`)
2. Starts Phoenix in prod (`MIX_ENV=prod mix phx.server`)

### Required environment variables

At minimum, set:

- `SECRET_KEY_BASE` (required in prod)

`mise run prod` will fail fast if `SECRET_KEY_BASE` is missing.

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

### Direct prod commands (without `mise run`)

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix phx.server
```

## User Guide (Quick)

1. Start server (`mise run dev` or `mise run prod`)
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
mise run test

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
  - Re-run project setup: `mise run setup`.
  - If needed, manually sync Python deps: `uv sync --project priv/python`.
- Port already in use:
  - Set a different port, for example: `PORT=4001 mise run prod`
