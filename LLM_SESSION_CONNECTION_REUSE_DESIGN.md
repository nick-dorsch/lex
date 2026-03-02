# LLM Session Connection Reuse Design (Mint + SSE)

## Goal

Reuse a single HTTP keep-alive connection for sequential OpenAI-compatible SSE requests within one LiveView reader session, while keeping failure handling and observability explicit.

## Current Baseline

- `Lex.LLM.Client` currently opens and closes a fresh Mint connection for every call to `stream_chat_completion/2`.
- Token-help requests originate in `LexWeb.Live.ReaderLive.Show` and flow through `Lex.Vocab.request_llm_help/5` into `Lex.LLM.Client`.
- TTFT is logged in `Lex.LLM.Client.process_sse_lines/6`, but logs do not identify whether the request used a reused or reconnected transport.

## Proposed Ownership Model

### Process boundaries

- LiveView process remains the session boundary and request orchestrator.
- Introduce `Lex.LLM.SessionConnection` (GenServer) as the owner of one Mint connection per LiveView PID.
- Introduce `Lex.LLM.SessionConnectionRegistry` (Registry + DynamicSupervisor) to create/lookup one `SessionConnection` process per LiveView PID.
- `SessionConnection` monitors the LiveView owner PID and terminates/cleans up when the owner exits.

### Lifecycle hooks

- In `LexWeb.Live.ReaderLive.Show`:
  - `mount/3`: register/ensure a session connection owner entry (lazy connect on first request).
  - `terminate/2`: request explicit cleanup, then allow monitor-driven fallback cleanup.
- Connection establishment remains lazy; no outbound connection is attempted until the first LLM request.

### Concrete module/function changes

- `lib/lex/llm/client.ex`
  - Add `stream_chat_completion/3` with opts for `session_owner` and request metadata.
  - Split request flow into:
    - `send_streaming_request/6` (uses an already-open Mint conn)
    - `stream_response/7` (existing parser logic, no ownership responsibilities)
  - Return transport error classification (`:recoverable_transport` vs `:non_recoverable_transport`) for retry logic.
- `lib/lex/llm/session_connection.ex` (new)
  - `request_stream(owner_pid, request_spec, callback)`
  - `ensure_connected/1`, `disconnect/2`, `maybe_reconnect/2`
  - Owns `%Mint.HTTP{}` and per-connection metadata (`connection_id`, `reuse_count`, timestamps).
- `lib/lex/llm/session_connection_registry.ex` (new)
  - `ensure_session(owner_pid)`
  - `lookup(owner_pid)`
  - `stop_session(owner_pid)`
- `lib/lex/vocab.ex`
  - Extend `request_llm_help/5` and downstream private calls with opts carrying `session_owner` (defaults to caller PID).
- `lib/lex_web/live/reader_live/show.ex`
  - Pass `self()` as `session_owner` when requesting token help.
  - Add cleanup call on terminate.

No ambiguity remains about ownership: Mint connection lifecycle belongs to the per-session GenServer, not to transient Task processes.

## Sequential Reuse Model

- Exactly one in-flight SSE request per `SessionConnection` process at a time.
- After `:done` (or terminal error), keep the connection open and mark it reusable.
- Next request in the same session reuses the existing conn if it is healthy.
- If server closes idle keep-alive between requests, first write/read failure triggers reconnect path automatically.

This model intentionally optimizes sequential token-help requests (the dominant LiveView usage), without supporting parallel multiplexing.

## Failure Signals and Reconnect Rules

Reconnect is required when any of the following occurs:

- `Mint.HTTP.request/5` returns `{:error, conn, reason}` where reason indicates closed/reset transport.
- `Mint.HTTP.stream/2` returns `{:error, conn, reason, _responses}` with transport-level failures (closed, timeout, protocol disconnect).
- Receive timeout in stream loop before terminal event (`after timeout -> :timeout`).
- Passive close detected via Mint messages (`Mint.TransportError`, TCP/TLS close).

Do **not** reconnect for:

- Provider HTTP status errors (4xx/5xx response from upstream).
- Request validation/auth errors.
- JSON/SSE parse-level data issues that are not transport disconnects.

## Transparent Retry Policy

- Allow a single transparent retry (`max_attempts = 2`) only for recoverable transport failures.
- Retry steps:
  1. Close stale conn (best effort).
  2. Reconnect.
  3. Re-issue the same POST request once.
- Guardrail: only retry when no terminal `{:chunk, _}` has been delivered yet to avoid duplicate partial output.
- If retry also fails, return `{:error, reason}` to existing LiveView error handling.

## TTFT/Reuse Logging Fields

Add structured log metadata on request start, first token, and completion:

- `llm_request_id` (DB id from `LlmHelpRequest`)
- `session_owner_pid`
- `connection_id` (stable for connection lifetime)
- `connection_state` (`new | reused | reconnected`)
- `reuse_count` (0 for first use, increments per successful request)
- `retry_attempt` (1 or 2)
- `reconnect_reason` (when applicable)
- `provider`, `model`
- `ttft_ms`

This explicitly enables TTFT analysis segmented by fresh vs reused vs reconnected transport.

## Implementation Order

1. Add session connection process + registry and ownership/cleanup hooks.
2. Refactor `Lex.LLM.Client` to operate on supplied/open connections and classify transport errors.
3. Thread `session_owner` opts from `ReaderLive.Show` through `Lex.Vocab` into the session connection API.
4. Add retry and structured logging metadata.
5. Add tests for reuse, reconnect-once behavior, and no-retry-after-first-chunk.
