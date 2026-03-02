# Agent Instructions for Lex

Lex is a Phoenix (Elixir) reading/vocabulary learning application with Python NLP components.

## Build Commands

### Elixir
```bash
# Install dependencies
mix deps.get

# Run tests (all)
mix test

# Run single test file
mix test test/lex_web/live/reader_live/show_test.exs

# Run specific test by line number
mix test test/lex_web/live/reader_live/show_test.exs:14

# Format code
mix format

# Check formatting
mix format --check-formatted

# Type checking
mix dialyzer

# Linting
mix credo
mix credo --strict

# Database setup
mix ecto.setup      # create + migrate
mix ecto.reset      # drop + setup
mix ecto.migrate    # run migrations
```

### Python (priv/python/)
```bash
# Run Python tests
cd priv/python && uv run pytest

# Run specific test file
uv run pytest tests/test_file.py

# Run specific test
uv run pytest tests/test_file.py::test_function_name
```

### Task Commands (via Taskfile)
```bash
# Run all tests (Elixir + Python)
task test

# Run NLP demo
task nlp
```

## Code Style Guidelines

### Elixir Conventions

**Formatting:**
- Run `mix format` before committing
- Follow `.formatter.exs` configuration
- Line length: default (98 chars)

**Module Structure:**
```elixir
defmodule Lex.ModuleName do
  @moduledoc """
  Brief description of module purpose.
  """

  use Ecto.Schema  # or appropriate use/import
  
  # Imports first, then aliases
  import Ecto.Changeset
  import Ecto.Query
  
  alias Lex.OtherModule
  alias Lex.Context.Module

  @type t :: %__MODULE__{}

  # Module attributes
  @valid_statuses ["uploaded", "ready"]

  # Schema definitions
  schema "table_name" do
    field(:name, :string)
    belongs_to(:user, Lex.Accounts.User)
    timestamps()
  end

  @doc false
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
```

**Naming:**
- Modules: `PascalCase` (e.g., `Lex.Library.Document`)
- Functions/variables: `snake_case` (e.g., `load_tokens/1`)
- Private functions: `snake_case` with `defp`
- Schema fields: `snake_case` atoms (e.g., `field(:user_id, :integer)`)
- Files: `snake_case.ex` matching module name

**Imports/Aliases:**
- Group `import` statements before `alias` statements
- Alias modules at the top level (e.g., `alias Lex.Repo`)
- Use `import` only when calling functions without module prefix frequently

**Error Handling:**
- Use `{:ok, result}` / `{:error, reason}` tuples
- Pattern match on results with `case` or `with`
- For validation errors, return `{:error, changeset}`
- Use `Repo.transaction/1` for multi-step operations

**LiveView Patterns:**
```elixir
defmodule LexWeb.LiveName do
  use LexWeb, :live_view

  alias Lex.Context
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, key: value)}
  end

  @impl true
  def handle_event("event_name", params, socket) do
    {:noreply, assign(socket, key: new_value)}
  end
end
```

### Test Conventions

**Elixir Tests:**
```elixir
defmodule LexWeb.ModuleTest do
  use Lex.ConnCase, async: false  # async: true when no DB/shared state

  import Phoenix.LiveViewTest

  alias Lex.Repo
  alias Lex.Context.Module

  describe "feature_name" do
    test "does something expected", %{conn: conn} do
      # Arrange
      data = create_data()
      
      # Act
      {:ok, _view, html} = live(conn, "/path")
      
      # Assert
      assert html =~ "expected content"
    end
  end

  # Helper functions at bottom
  defp create_data do
    # ...
  end
end
```

**Test Guidelines:**
- Use `describe` blocks to group related tests
- Helper functions for test data creation (e.g., `create_user/0`)
- Use unique values for fields requiring uniqueness (e.g., `System.unique_integer()`)
- End-to-end LiveView tests use `Phoenix.LiveViewTest`

### Python (NLP Pipeline)

**Formatting:**
- Use `ruff` or standard Python formatting
- Follow `pyproject.toml` settings

**Structure:**
- Organize code in `priv/python/lex_nlp/`
- Tests in `priv/python/tests/`
- Use type hints where appropriate

## Project Architecture

**Contexts:**
- `Lex.Library` - Document/section management
- `Lex.Reader` - Reading progress, events
- `Lex.Vocab` - Vocabulary, lexemes, user state
- `Lex.Accounts` - User management
- `Lex.Text` - Sentences, tokens

**Web Layer:**
- `LexWeb` - Router, controllers, LiveViews
- `LexWeb.Live.*` - LiveView modules
- `LexWeb.Components.*` - Shared components

**Database:**
- SQLite3 via Ecto
- Migrations in `priv/repo/migrations/`
- Schemas define foreign keys and constraints explicitly

## Important Notes

- **No Cursor/Copilot rules** currently configured
- Use `mise` for tool version management (Erlang 26.2, Elixir 1.16, Python 3.13)
- Python NLP requires spaCy model: `python -m spacy download es_core_news_md`
- Run full test suite with `task test` before committing
