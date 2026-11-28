---
control_id: F-20261126-starred-tasks-for-tasklist
kind: plan
repo: agentic-sdlc-demo/app-source
team: taskslist
drafted_by: system:sdlc-bot
published: '2026-11-28T16:16:37Z'
previous:
  path: features/F-20261126-starred-tasks-for-tasklist/design.md
  commit: 2824fdd9df41d450be7149a6eff47f115f539450
  merged_by: shaheenks
jira:
- TAS-11
- TAS-12
- TAS-13
- TAS-14
- TAS-15
- TAS-16
---

# TAS-11: plan for agentic-sdlc-demo/app-source

| | |
|---|---|
| Design | features/F-20261126-starred-tasks-for-tasklist/design.md |
| Feature Size | 11 points |
| Stories | TAS-12 (2 pts), TAS-13 (2 pts), TAS-14 (2 pts), TAS-15 (3 pts), TAS-16 (2 pts) |
| Repository | agentic-sdlc-demo/app-source, branch feature/F-20261126-starred-tasks-for-tasklist |

## Summary

This plan implements full-stack support for starred tasks across SQLite persistence, Express server APIs, web client types, UI components, and test suites. Tasks can be starred or unstarred via PATCH requests and interactive row toggles, pinned to the top of open task lists, filtered via a "Starred" chip in the filter bar, and automatically unstarred upon completion.

## Story coverage & Acceptance Criteria

### TAS-12: Schema & Persistence for Starred Tasks (2 points)
- `tasks` table includes a `starred` column: `INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1))`.
- Boot-time migration detects existing databases lacking `starred` and alters the table idempotently.
- A composite index `idx_tasks_list_starred_created ON tasks(listId, starred DESC, createdAt DESC)` is created.
- Newly created tasks default to `starred: 0` (`false`).

### TAS-13: API Support for Starring and Unstarring (2 points)
- `PATCH /api/tasks/:id` accepts `{ "starred": boolean }`, validates the type, and updates the task.
- Invalid payloads (e.g., non-boolean values) return HTTP 400 `validation_error`.
- Task JSON serialization outputs `starred` as a boolean (`true`/`false`).
- Marking a task complete via `POST /api/tasks/:id/complete` automatically resets `starred` to `0` (`false`).

### TAS-14: API List Sorting and Filtering (2 points)
- `GET /api/lists/:listId/tasks` orders tasks by `starred DESC, createdAt DESC`.
- `GET /api/lists/:listId/tasks?starred=true` returns only starred tasks.
- `GET /api/lists/:listId/tasks?starred=false` returns only unstarred tasks.
- Invalid `starred` query parameter values return HTTP 400.

### TAS-15: Star Toggle UI and Task Ordering (3 points)
- Each open task row renders a star toggle button with accessible labels (`Star <title>` / `Unstar <title>`).
- Clicking the star button optimistically updates the UI and sends a PATCH request to toggle `starred`.
- Open tasks are sorted with starred items appearing before unstarred items, maintaining `createdAt DESC` within each group.
- Completing a task removes its starred status immediately in the UI.

### TAS-16: Starred Tasks Filter & End-to-End Flow (2 points)
- A "Starred" filter chip in the filter bar toggles between filtering for starred tasks and showing all tasks.
- Client state correctly synchronizes with the server query parameter.
- Full starred lifecycle (star, reorder, filter, complete, reset) functions end-to-end and is validated via Playwright E2E tests.

## Flows

### 1. Starring / Unstarring a Task
- **Trigger**: User clicks the star button on a task row in `TaskRow.tsx`.
- **Happy path**:
  1. `TaskRow` calls `onUpdate(task.id, { starred: !task.starred })`.
  2. `App.tsx` performs an optimistic update on local state, updating the task's `starred` property and immediately re-sorting the open task list.
  3. `apiClient.patchTask(id, { starred })` sends `PATCH /api/tasks/:id`.
  4. Server persists the change, serializes the updated row, and returns HTTP 200 with `{ ..., starred: boolean }`.
  5. `App.tsx` reconciles state with server response.
- **Error path**:
  1. Server returns a 4xx/5xx error or the network request fails.
  2. `App.tsx` catches the failure, rolls back the optimistic update to the previous task state, and displays an error alert via the existing `useToast` context helper (`showToast(error.message, { type: 'error' })`).

## Changes

| File | Change | Story |
|---|---|---|
| `server/src/schema.sql` | Add `starred INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1))` to `tasks` table; add composite index `idx_tasks_list_starred_created ON tasks(listId, starred DESC, createdAt DESC)` | TAS-12, TAS-14 |
| `server/src/db.ts` | Add boot migration `migrateSchema(): void` checking `PRAGMA table_info(tasks)` for `starred` column, issuing `ALTER TABLE tasks ADD COLUMN starred...` and index creation if missing | TAS-12 |
| `server/src/routes/tasks.ts` | Add `serializeTask(row: TaskRow): SerializedTask` converting `starred` integer (`0`/`1`) to boolean (`false`/`true`) across all task responses; add `starred: z.boolean().optional()` to `patchTaskSchema`; whitelist `starred` in `PATCH /tasks/:id`; update `POST /tasks/:id/complete` to reset `starred = 0`; update `GET /lists/:listId/tasks` to handle `?starred=true\|false` filter and sort `ORDER BY starred DESC, createdAt DESC` | TAS-12, TAS-13, TAS-14 |
| `web/src/api/client.ts` | Add `starred: boolean` to `Task` interface; add `starred?: boolean` to `TaskFilters`; define `TaskPatch` type including `starred?: boolean`; append `starred` query parameter in `listTasks` | TAS-14, TAS-15 |
| `web/src/components/TaskRow.tsx` | Add star button to `.task-row-main` with accessible labels (`Star <title>` / `Unstar <title>`); invoke `onUpdate(task.id, { starred: !task.starred })` on click | TAS-15 |
| `web/src/components/TaskList.tsx` | Declaratively sort `open` tasks so starred items (`starred === true`) precede unstarred items while preserving `createdAt DESC` ordering within each group | TAS-15 |
| `web/src/styles.css` | Add styling for `.star-btn` toggle (active/starred states, hover focus, and alignment within `.task-row-main`) | TAS-15 |
| `web/src/components/FilterBar.tsx` | Add `starred?: boolean` to `Filters` interface; render "Starred" filter chip toggling `filters.starred` | TAS-16 |
| `web/src/App.tsx` | Forward `filters.starred` to `listTasks`; handle optimistic UI star updates in `handleUpdate`; clear `starred` optimistically on `handleToggle` completion; use `useToast` (`showToast`) to notify user on mutation error rollback | TAS-15, TAS-16 |
| `server/tests/tasks.test.ts` | Add tests for schema migration, boolean serialization, PATCH mutation and validation (`400 validation_error`), completion reset to `starred: false`, and `GET` sort/filter by starred | TAS-12, TAS-13, TAS-14 |
| `web/tests/TaskList.test.tsx` | Add unit tests verifying starred open tasks render above unstarred open tasks regardless of array input ordering | TAS-15 |
| `web/tests/TaskRow.test.tsx` | New unit tests verifying accessible labels (`Star <title>` / `Unstar <title>`) and click event emitting `onUpdate(task.id, { starred: ... })` | TAS-15 |
| `web/tests/FilterBar.test.tsx` | New unit tests verifying "Starred" filter button rendering and toggle callback behavior | TAS-16 |
| `web/e2e/tasklist.spec.ts` | Add Playwright E2E test covering the task starring lifecycle: star task, verify top-of-list reordering, filter by starred, and verify completion resets star | TAS-16 |

## Order of work

1. **Database schema and boot migration (TAS-12, TAS-14)**:
   - Update `server/src/schema.sql` with `starred` column and composite index `idx_tasks_list_starred_created`.
   - Implement `migrateSchema()` in `server/src/db.ts` to inspect table info and safely alter existing databases.
2. **Server routes, serialization, and validation (TAS-12, TAS-13, TAS-14)**:
   - Define `serializeTask` in `server/src/routes/tasks.ts` ensuring all task responses return `starred: boolean`.
   - Update `patchTaskSchema` and `PATCH /tasks/:id` to accept and persist `starred`.
   - Update `POST /tasks/:id/complete` to synchronously set `starred = 0`.
   - Update `GET /lists/:listId/tasks` query builder to sort by `starred DESC, createdAt DESC` and filter by `req.query.starred`.
3. **Server integration tests (TAS-12, TAS-13, TAS-14)**:
   - Add integration tests in `server/tests/tasks.test.ts` covering schema migration, PATCH validation, completion reset, and filtered list sorting.
4. **Web API client types (TAS-14, TAS-15)**:
   - Extend `Task`, `TaskFilters`, and `TaskPatch` in `web/src/api/client.ts`.
   - Serialize `starred` parameter in `listTasks`.
5. **Web UI star toggling and sorting (TAS-15)**:
   - Add accessible star toggle button and click handlers to `web/src/components/TaskRow.tsx`.
   - Add CSS rules for star button in `web/src/styles.css`.
   - Add declarative open task sorting (`starred` first) in `web/src/components/TaskList.tsx`.
6. **Web UI filter bar and state management (TAS-15, TAS-16)**:
   - Add "Starred" filter chip to `web/src/components/FilterBar.tsx`.
   - Update `web/src/App.tsx` to handle filter propagation, optimistic star toggles, optimistic completion reset, and error toast handling via `useToast`.
7. **Frontend component tests (TAS-15, TAS-16)**:
   - Update `web/tests/TaskList.test.tsx` with starred order assertions.
   - Create `web/tests/TaskRow.test.tsx` and `web/tests/FilterBar.test.tsx` using Vitest and React Testing Library.
8. **End-to-end integration test (TAS-16)**:
   - Add starred task lifecycle test to `web/e2e/tasklist.spec.ts`.

## Tests

- `server/tests/tasks.test.ts`:
  - **TAS-12**: Test database initialization returns `starred: false` (boolean) on all created tasks. Test check constraint on `starred` rejecting values outside `0` and `1`.
  - **TAS-13**: Test `PATCH /api/tasks/:id` with `{"starred": true}` returns HTTP 200 with `starred: true`. Test `PATCH /api/tasks/:id` with invalid type `{"starred": "yes"}` returns HTTP 400 with `validation_error`. Test `POST /api/tasks/:id/complete` on a starred task returns HTTP 200 with `status: "done"` and `starred: false`.
  - **TAS-14**: Test `GET /api/lists/:listId/tasks` returns starred tasks before unstarred tasks. Test `GET /api/lists/:listId/tasks?starred=true` returns only starred tasks. Test `GET /api/lists/:listId/tasks?starred=invalid` returns HTTP 400.
- `web/tests/TaskRow.test.tsx`:
  - **TAS-15**: Verify unstarred task renders outline star button with accessible label `Star <task title>`. Verify starred task renders filled star button with accessible label `Unstar <task title>`. Verify clicking star button triggers `onUpdate(task.id, { starred: true })` or `{ starred: false }`.
- `web/tests/TaskList.test.tsx`:
  - **TAS-15**: Verify open tasks with `starred: true` render before open tasks with `starred: false` regardless of raw input order.
- `web/tests/FilterBar.test.tsx`:
  - **TAS-16**: Verify "Starred" filter chip renders and clicking it calls `onChange` with `{ ...filters, starred: true }` and toggles off to `undefined`.
- `web/e2e/tasklist.spec.ts`:
  - **TAS-16**: End-to-end test creating task A and task B, clicking star on task A, asserting task A appears before task B, toggling "Starred" chip and asserting task B is hidden, completing task A, and verifying it moves to "Done" with unstarred state.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Existing SQLite DB missing `starred` column causes crash on launch | High | `migrateSchema()` in `server/src/db.ts` uses `PRAGMA table_info(tasks)` to inspect existing columns and idempotently add `starred` before requests are accepted. |
| SQLite integer `0`/`1` deserializes to number in JSON responses, breaking boolean checks in UI | Medium | Centralize all task serialization through `serializeTask` in `server/src/routes/tasks.ts`, tested by Supertest assertions. |
| Inconsistent client ordering during optimistic updates | Low | `TaskList.tsx` enforces declarative sorting on open tasks by `starred DESC, createdAt DESC` on every render. |

## Out of scope

- Manual drag-and-drop reordering within starred or unstarred sections.
- Multi-tier priority stars (e.g. 1 to 5 star ratings) or custom star color tags.
- Starred task push notifications, email alerts, or due-date reminder integrations.
- Starring or favoriting entire task lists.
- Restoring historical starred state when a completed task is reopened.

## Open questions

None. All questions raised during requirements analysis were resolved in `features/F-20261126-starred-tasks-for-tasklist/design.md` (reopening leaves tasks unstarred; creation defaults to unstarred; completed tasks in "Done" retain no special badge).
