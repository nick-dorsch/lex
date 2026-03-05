# Lex Architecture Diagrams

This document provides Mermaid diagrams for the Lex application architecture.

## 1) System Context

```mermaid
flowchart LR
    U[User] -->|Browser| LV[Phoenix LiveView UI]
    LV --> Ctx[Lex Contexts]
    Ctx --> DB[(SQLite via Ecto)]
    Ctx --> NLP[Python NLP CLI]
    Ctx --> LLM[LLM Provider API]
    Ctx --> FS[Calibre Library Filesystem]

    subgraph BEAM[Elixir/Phoenix App]
      LV
      Ctx
      DB
    end

    subgraph Python[Python Runtime]
      NLP
    end
```

## 2) Phoenix + Domain Module Layout

```mermaid
flowchart TB
    Endpoint[LexWeb.Endpoint] --> Router[LexWeb.Router]
    Router --> LibraryLive[LibraryLive.Index]
    Router --> ReaderLive[ReaderLive.Show]
    Router --> StatsLive[StatsLive.Index]
    Router --> CoverController[CalibreCoverController]

    LibraryLive --> LibraryCtx[Lex.Library]
    LibraryLive --> VocabCtx[Lex.Vocab]
    ReaderLive --> ReaderCtx[Lex.Reader]
    ReaderLive --> VocabCtx
    StatsLive --> ReaderCtx
    StatsLive --> VocabCtx

    LibraryCtx --> Repo[Lex.Repo]
    ReaderCtx --> Repo
    VocabCtx --> Repo
    Repo --> SQLite[(SQLite DB)]
```

## 3) EPUB Import + NLP Processing Pipeline

```mermaid
sequenceDiagram
    participant User
    participant LibraryLive as LibraryLive.Index
    participant Library as Lex.Library
    participant Tracker as ImportTracker
    participant Worker as ImportWorker/Task
    participant EPUB as Lex.Library.EPUB
    participant NLP as Lex.Text.NLP
    participant Py as priv/python/lex_nlp.py
    participant Repo as Lex.Repo

    User->>LibraryLive: Click "Import"
    LibraryLive->>Library: import_epub_async(file_path, user_id)
    Library->>Tracker: start_import(file_path, user_id)
    Tracker-->>LibraryLive: publish :import_started
    Library->>Worker: start supervised task
    Worker->>EPUB: parse metadata + chapters
    Worker->>Repo: insert document + sections
    Worker->>NLP: process_text(chapter_text)
    NLP->>Py: System.cmd("python", ...)
    Py-->>NLP: JSON sentences/tokens
    NLP-->>Worker: parsed sentence/token data
    Worker->>Repo: insert sentences/tokens/lexemes
    Worker->>Repo: set document status = ready
    Worker->>Tracker: complete import
    Tracker-->>LibraryLive: publish :import_progress/:import_completed
    LibraryLive-->>User: UI updates in real time
```

## 4) Reading + Vocabulary State Flow

```mermaid
flowchart LR
    ReaderUI[Reader LiveView] --> ReaderCtx[Lex.Reader]
    ReaderUI --> VocabCtx[Lex.Vocab]

    ReaderCtx --> RP[(reading_positions)]
    ReaderCtx --> USS[(user_sentence_states)]
    ReaderCtx --> Events[(reading_events)]

    VocabCtx --> ULS[(user_lexeme_states)]
    VocabCtx --> LLMReq[(llm_help_requests)]

    ReaderUI -->|space/help| LLMClient[Lex.LLM.Client]
    LLMClient --> ExternalLLM[OpenAI-compatible API]
    ExternalLLM --> LLMClient
    LLMClient --> VocabCtx
```

## 5) Runtime Configuration and Environments

```mermaid
flowchart TB
    subgraph Dev[Development]
      DevCmd[mise run dev / mix phx.server]
      DevCfg[config/dev.exs]
      DevDB[(priv/repo/lex_dev.db)]
      Tailwind[tailwind --watch]
      DevCmd --> DevCfg --> DevDB
      DevCfg --> Tailwind
    end

    subgraph Prod[Production Mode]
      ProdCmd[mise run prod / MIX_ENV=prod mix phx.server]
      Assets[MIX_ENV=prod mix assets.deploy]
      Runtime[config/runtime.exs]
      Env[SECRET_KEY_BASE, PORT, HOST, etc]
      ProdDB[(~/.lex/lex.db)]
      ProdCmd --> Assets
      ProdCmd --> Runtime
      Env --> Runtime --> ProdDB
    end
```

## 6) Supervision Tree (Simplified)

```mermaid
flowchart TD
    App[Lex.Application] --> Sup[Lex.Supervisor]
    Sup --> Repo[Lex.Repo]
    Sup --> Telemetry[LexWeb.Telemetry]
    Sup --> PubSub[Phoenix.PubSub]
    Sup --> Tracker[Lex.Library.ImportTracker]
    Sup --> TaskSup[Task.Supervisor: ImportTaskSupervisor]
    Sup --> Endpoint[LexWeb.Endpoint]

    TaskSup --> ImportTasks[Async Import Workers]
    Tracker --> PubSub
    Endpoint --> PubSub
```
