# SPEC-001: Shared tasklist for small teams

- **Intent:** [INT-001](../intents/INT-001-tasklist.md)
- **Status:** committed
- **Skills applied:** `api-standards`, `security-baseline`, `ui-brand` (sdlc-control@governance-v0)

## Data model

```
List
  id            text (uuid), primary key
  name          text, 1-100 chars, required
  createdAt     text (ISO-8601 UTC)
  updatedAt     text (ISO-8601 UTC)

Task
  id            text (uuid), primary key
  listId        text, foreign key -> List.id, required
  title         text, 1-200 chars, required
  status        text, enum: "open" | "done", default "open"
  priority      text, enum: "low" | "medium" | "high", default "medium"
  dueDate       text (ISO-8601 date) | null
  createdAt     text (ISO-8601 UTC)
  updatedAt     text (ISO-8601 UTC)
  completedAt   text (ISO-8601 UTC) | null
```

A workspace has exactly one default List seeded on first run (no multi-team model — non-goal per INT-001). Deleting a List cascades to its Tasks.

## API contract

Per `skills/api-standards`: plural kebab-case resources, standard error shape, pagination on lists, ISO-8601 timestamps, `/healthz` and `/metrics`.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/lists` | paginated (`limit`, `offset`) |
| `POST` | `/api/lists` | body `{ name }`; 201 + `Location` |
| `GET` | `/api/lists/:listId/tasks` | paginated; filters `status`, `priority`, `dueBefore` |
| `POST` | `/api/lists/:listId/tasks` | body `{ title, priority?, dueDate? }`; 201 + `Location` |
| `PATCH` | `/api/tasks/:id` | partial update (`title`, `priority`, `dueDate`) |
| `POST` | `/api/tasks/:id/complete` | sets `status: done`, `completedAt: now`; 409 if already done |
| `POST` | `/api/tasks/:id/reopen` | sets `status: open`, `completedAt: null`; 409 if already open |
| `DELETE` | `/api/tasks/:id` | 204 |
| `GET` | `/healthz` | liveness, no auth |
| `GET` | `/metrics` | `p50`/`p95`/`p99` latency ms, `errorCount`, `requestCount` — feeds Stage 6 detection |

Error responses use the standard shape: `{ "error": { "code": "...", "message": "..." } }`. Unknown body fields are rejected with `400` / `code: "unknown_field"`.

## UI

Per `skills/ui-brand`: recognizable naming, explicit empty/loading/error states, immediate feedback, keyboard accessibility, one primary action per view, light/dark support.

**Screens:**

1. **Task list** (default view) — grouped by status (Open, then Done, collapsed by default). Each row: checkbox (complete/reopen), title, priority chip, due-date badge (red if overdue, amber if due today). Primary action: "Add task" (single text input, Enter to submit — title only required, matching the 5-second capture goal in INT-001).
2. **Task detail** (inline expand, not a separate route) — edit title, priority, due date; Delete with a confirm step (destructive action, never the default focus).
3. **Filters** — status and priority as toggle chips above the list; "Due today" / "Overdue" quick filters.

**States:** empty list shows "No tasks yet — add your first one above" (not a bare blank screen); a failed load shows "Couldn't load tasks — retry" with a retry button, never a raw error string; optimistic UI on complete/reopen with rollback + toast on failure.

## Security requirements

Per `skills/security-baseline`, applied at generation time:

- All request bodies/params validated (type, length, allowlisted fields) before touching the database; reject unknown fields.
- All queries parameterized — no string-built SQL, including in filters (`status`, `priority`, `dueBefore`).
- Mutating endpoints rate-limited (demo threshold: 60 req/min per IP).
- No task content or IDs appear in server error responses; errors use the standard shape only.
- Response headers on all HTML/API responses: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, a restrictive CSP on the served HTML.
- Mutations write a structured audit log line (actor placeholder `"local-user"` for the single-workspace MVP, action, entity id, timestamp) — no task titles/content in the log line.
- `.env`/DB path/credentials never hard-coded; `DB_PATH` from environment only (matches `deploy/docker-compose.yml`).

## Acceptance criteria

- **Capture:** typing a title and pressing Enter creates a task and it appears in the Open group within 1 request round-trip; empty/whitespace-only title is rejected client- and server-side.
- **Complete/reopen:** toggling a checkbox updates status optimistically; a 409 from a race (already done/open) reconciles the UI to server state without an error toast.
- **Filters:** selecting "Overdue" shows only tasks with `dueDate < today` and `status: open`; combining with a priority chip narrows further (AND, not OR).
- **Delete:** requires a confirm step; deleted tasks return 404 on subsequent fetch.
- **Validation:** a title over 200 chars, an unknown body field, or an invalid `priority` value all return 400 with a field-specific `message`.
- **Metrics:** `/metrics` reflects request volume and latency after a scripted burst of 50 requests, within one sampling interval.
- **Security eval:** the implementing PRs pass `evals/cases/endpoint-security.md` (parameterized SQL, validation, standard error shape) with zero findings in Stage 5 review.
