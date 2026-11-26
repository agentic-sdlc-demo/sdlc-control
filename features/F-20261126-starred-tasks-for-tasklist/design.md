---
control_id: F-20261126-starred-tasks-for-tasklist
kind: design
team: taskslist
drafted_by: shaheenks@shaheenks.altostrat.com
published: '2026-11-26T13:15:12Z'
previous:
  path: features/F-20261126-starred-tasks-for-tasklist/feature.md
  commit: 33132bbba460175d382c8f024f179aeb390d09f7
  approved: true
jira:
- TAS-11
---

# TAS-11: Starred Tasks for Tasklist

| | |
|---|---|
| Feature | TAS-11 |
| Stories | TAS-12, TAS-13, TAS-14, TAS-15, TAS-16 |
| Target repositories | agentic-sdlc-demo/app-source (pull request) |
| Status | Draft |

## Context

Tasklist provides task tracking with status, priority, and due dates, but open tasks are presented solely in reverse-chronological order (`createdAt DESC`). Users with numerous tasks struggle to visually distinguish urgent or high-value items without changing priority levels.

This feature introduces first-class support for starring tasks:
- SQLite schema migration adding a `starred` integer column with index support.
- API endpoints supporting mutations via `PATCH /api/tasks/:id` and filter/sort parameters on `GET /api/lists/:listId/tasks`.
- Automatic clearing of the starred status upon task completion in `POST /api/tasks/:id/complete`.
- Web UI star toggles in `TaskRow.tsx`, declarative pinned sorting in `TaskList.tsx`, and a "Starred" filter chip in `FilterBar.tsx`.

## Goals

- **Schema Persistence & Migration**: Persist task starred state as an SQLite integer (`0` or `1`) with backward-compatible boot migration via `PRAGMA table_info` and composite indexing.
- **API Filtering & Prioritized Sorting**: Ensure task list queries order by `starred DESC, createdAt DESC` by default, serialize `starred` as a boolean in responses, and support `?starred=true|false` query parameters.
- **Safe State Transitions**: Automatically unstar tasks when completed, validate mutations via Zod, and enforce whitelist field extraction in PATCH handlers.
- **Interactive UI with Responsive Feedback**: Provide a 1-click star toggle in `TaskRow` updating optimistically within 100ms, keep open starred tasks pinned to the top in `TaskList`, and allow quick isolation via a "Starred" filter chip.
- **End-to-End Validation**: Cover schema migrations, API contracts, edge cases, and user workflows with Supertest and Playwright test suites.

## Non-goals

- Drag-and-drop manual reordering among starred or unstarred items.
- Multi-tier priority stars (e.g. 1 to 5 star ratings) or custom star color tags.
- Starred notifications, email summaries, or due-date escalation webhooks.
- Starring or favoriting lists themselves (`lists` table is unchanged).
- Retaining or restoring historical starred state when a completed task is reopened.

## Design

### Components

1. **Database Layer (`server/src/db.ts` & `server/src/schema.sql`)**:
   - Inspects existing table schema using SQLite `PRAGMA table_info(tasks)` at startup.
   - Executes `ALTER TABLE tasks ADD COLUMN starred INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1));` if missing.
   - Creates composite index `idx_tasks_list_starred_created` on `(listId, starred DESC, createdAt DESC)`.

2. **Server API Router (`server/src/routes/tasks.ts`)**:
   - Updates `createTaskSchema` and `patchTaskSchema` using Zod.
   - Updates `TaskRow` interface and adds `serializeTask(row: TaskRow): SerializedTask` converting `starred` integer (`0`/`1`) to boolean (`false`/`true`).
   - Updates `GET /api/lists/:listId/tasks` to handle `req.query.starred` and orders by `starred DESC, createdAt DESC`.
   - Updates `PATCH /api/tasks/:id` whitelist to include `starred`, persisting `1` or `0`.
   - Updates `POST /api/tasks/:id/complete` to reset `starred = 0` synchronously.

3. **Web API Client (`web/src/api/client.ts`)**:
   - Extends `Task` interface with `starred: boolean`.
   - Extends `TaskFilters` interface with `starred?: boolean`.
   - Updates `updateTask` payload type signature to accept `starred?: boolean`.
   - Appends `starred` to `URLSearchParams` in `listTasks`.

4. **Web UI Components**:
   - **`TaskRow.tsx`**: Renders an accessible star toggle button (`aria-label="Star <title>"` or `aria-label="Unstar <title>"`). Emits `onUpdate(task.id, { starred: !task.starred })`.
   - **`TaskList.tsx`**: Declaratively sorts open tasks by `starred DESC, createdAt DESC` prior to rendering.
   - **`FilterBar.tsx`**: Renders a "Starred" filter chip alongside status and priority chips, toggling `filters.starred`.
   - **`App.tsx`**: Manages filter state, passes `starred` to `listTasks`, handles optimistic star toggling, and clears star state optimistically on complete.

### Interfaces

#### REST API Endpoints

- **`GET /api/lists/:listId/tasks`**
  - Query parameters:
    - `starred` (optional, string): `"true"` or `"false"`. Any other value returns HTTP 400 with `validation_error`.
    - `status`, `priority`, `dueBefore`, `limit`, `offset` (existing parameters preserved).
  - Ordering: `ORDER BY starred DESC, createdAt DESC LIMIT ? OFFSET ?`.
  - Response (HTTP 200):
    ```json
    {
      "items": [
        {
          "id": "c1f7b4e2-...",
          "listId": "d2a6c1e0-...",
          "title": "Quarterly taxes",
          "status": "open",
          "priority": "high",
          "dueDate": "2025-04-15",
          "starred": true,
          "createdAt": "2025-03-30T10:00:00.000Z",
          "updatedAt": "2025-03-30T10:05:00.000Z",
          "completedAt": null
        }
      ],
      "total": 1
    }
    ```

- **`PATCH /api/tasks/:id`**
  - Validation schema (`patchTaskSchema`):
    ```ts
    const patchTaskSchema = z
      .object({
        title: z.string().trim().min(1).max(200).optional(),
        priority: priorityEnum.optional(),
        dueDate: dateShape.nullable().optional(),
        starred: z.boolean().optional(),
      })
      .strict()
      .refine((obj) => Object.keys(obj).length > 0, { message: "at least one field required" });
    ```
  - Whitelist: `["title", "priority", "dueDate", "starred"] as const`.
  - Invalid value (e.g. `{"starred": "yes"}`) triggers HTTP 400 with:
    ```json
    {
      "error": {
        "code": "validation_error",
        "message": "Expected boolean, received string"
      }
    }
    ```
  - Response (HTTP 200): Returns the updated serialized task with `starred: boolean`.

- **`POST /api/tasks/:id/complete`**
  - Behavior: Marks task as `done`, sets `completedAt = now`, `updatedAt = now`, and resets `starred = 0`.
  - Response (HTTP 200): Returns serialized task with `status: "done"` and `starred: false`.

- **`POST /api/tasks/:id/reopen`**
  - Behavior: Reopens task (`status = 'open'`, `completedAt = NULL`, `updatedAt = now`). Task remains `starred: false`.

#### TypeScript Client & Component Signatures

- `web/src/api/client.ts`:
  ```ts
  export interface Task {
    id: string;
    listId: string;
    title: string;
    status: Status;
    priority: Priority;
    dueDate: string | null;
    starred: boolean;
    createdAt: string;
    updatedAt: string;
    completedAt: string | null;
  }

  export interface TaskFilters {
    status?: Status;
    priority?: Priority;
    dueBefore?: string;
    starred?: boolean;
  }

  export type TaskPatch = Partial<Pick<Task, "title" | "priority" | "dueDate" | "starred">>;

  export async function updateTask(id: string, patch: TaskPatch): Promise<Task>;
  ```

- `web/src/components/TaskRow.tsx`:
  ```ts
  interface Props {
    task: Task;
    onToggle: (task: Task) => void;
    onUpdate: (id: string, patch: TaskPatch) => void;
    onDelete: (id: string) => void;
  }
  ```

- `web/src/components/FilterBar.tsx`:
  ```ts
  export interface Filters {
    status?: Status;
    priority?: Priority;
    dueToday?: boolean;
    overdue?: boolean;
    starred?: boolean;
  }
  ```

### Data

#### Schema Definitions (`server/src/schema.sql`)

```sql
CREATE TABLE IF NOT EXISTS lists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  listId TEXT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','done')),
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high')),
  dueDate TEXT,
  starred INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1)),
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  completedAt TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_listId ON tasks(listId);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_list_starred_created ON tasks(listId, starred DESC, createdAt DESC);
```

#### Boot-Time Migration (`server/src/db.ts`)

```ts
function migrateSchema(): void {
  const columns = db.pragma("table_info(tasks)") as Array<{ name: string }>;
  const hasStarred = columns.some((col) => col.name === "starred");
  if (!hasStarred) {
    db.exec("ALTER TABLE tasks ADD COLUMN starred INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1));");
  }
  db.exec("CREATE INDEX IF NOT EXISTS idx_tasks_list_starred_created ON tasks(listId, starred DESC, createdAt DESC);");
}
```

#### Task Serialization (`server/src/routes/tasks.ts`)

SQLite stores integers (`0` or `1`), but clients require a boolean:

```ts
interface TaskRow {
  id: string;
  listId: string;
  title: string;
  status: "open" | "done";
  priority: "low" | "medium" | "high";
  dueDate: string | null;
  starred: number;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
}

export interface SerializedTask extends Omit<TaskRow, "starred"> {
  starred: boolean;
}

function serializeTask(row: TaskRow): SerializedTask {
  return {
    ...row,
    starred: Boolean(row.starred),
  };
}
```

Every route returning task data (`GET`, `POST`, `PATCH`, `complete`, `reopen`) maps rows through `serializeTask`.

### Flows

#### 1. Starring / Unstarring a Task
```
User clicks Star Icon in TaskRow
  │
  ├──> Optimistic UI update in App.tsx (toggles task.starred, re-sorts TaskList within <100ms)
  │
  └──> PATCH /api/tasks/:id { "starred": true }
         │
         ├──> validateBody(patchTaskSchema) validates type is boolean
         ├──> db.prepare("UPDATE tasks SET starred = ?, updatedAt = ? WHERE id = ?").run(1, now, id)
         └──> Returns HTTP 200 with serialized task { ...task, starred: true }
         (On failure: reverts optimistic state and displays toast error)
```

#### 2. Completing a Starred Task
```
User clicks Checkbox on a starred open task
  │
  ├──> Optimistic UI: sets status = "done", starred = false, moves task to Done section
  │
  └──> POST /api/tasks/:id/complete
         │
         ├──> Checks status !== "done" (else 409)
         ├──> db.prepare("UPDATE tasks SET status = 'done', completedAt = ?, updatedAt = ?, starred = 0 WHERE id = ?")
         └──> Returns HTTP 200 with { status: "done", completedAt: "...", starred: false }
```

#### 3. Filtering by Starred
```
User toggles "Starred" chip in FilterBar
  │
  ├──> App.tsx updates filters.starred = true
  └──> listTasks(listId, { starred: true, ...otherFilters })
         │
         └──> GET /api/lists/:listId/tasks?starred=true
                │
                ├──> Appends SQL clause "starred = 1"
                └──> Returns only starred tasks matching other active filters
```

## Alternatives considered

1. **Boolean storage in SQLite**:
   - *Option*: SQLite does not possess a native boolean datatype and maps boolean literals to integers `0` and `1`.
   - *Decision*: Explicitly use `INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1))` to guarantee strict data integrity at the database engine level while serializing to true JavaScript booleans in API responses.

2. **Client-side only sorting vs. Database ordering**:
   - *Option*: Fetch all tasks ordered by `createdAt DESC` and sort starred tasks in memory on the client.
   - *Decision*: Apply `ORDER BY starred DESC, createdAt DESC` directly in SQLite supported by composite index `(listId, starred DESC, createdAt DESC)`. This guarantees pagination (`limit`/`offset`) remains stable and accurate as list sizes grow. Additionally, `TaskList.tsx` declaratively sorts in the UI to guarantee instant optimistic placement when stars are toggled.

3. **Retaining star state upon task completion**:
   - *Option*: Keep tasks starred even after they are marked done.
   - *Decision*: Per acceptance criteria, completion clears the star (`starred = 0`). Resolved tasks should not clutter prioritized views.

## Security and privacy

- **Strict Payload Validation**: `patchTaskSchema` is defined with `.strict()`. Unrecognized fields are rejected with HTTP 400. `starred` must be a literal boolean; string coercions such as `"yes"` or `"1"` fail validation.
- **SQL Injection Prevention**: All queries in `server/src/routes/tasks.ts` use parameterized SQL statements via `better-sqlite3`. Dynamic WHERE clauses append `?` placeholders with bound parameter values.
- **Audit Logging**: Existing `audit("task.update", id)` and `audit("task.complete", id)` calls in `server/src/routes/tasks.ts` are preserved for star state changes and completion resets.
- **Rate Limiting**: Mutation routes continue using the `rateLimit` middleware.

## Test approach

### 1. Database & Server Integration Tests (`server/tests/tasks.test.ts`)
- **Migration & Defaults**:
  - Verify that initializing the database runs the migration and all existing tasks have `starred: false` (serialized).
  - Test SQLite schema directly to confirm default `0` and check constraint rejecting values other than `0` and `1`.
- **PATCH Validation & Persistence**:
  - `PATCH /api/tasks/:id` with `{"starred": true}` returns HTTP 200 with `starred: true`.
  - `PATCH /api/tasks/:id` with `{"starred": "yes"}` returns HTTP 400 with `code: "validation_error"`.
  - `PATCH /api/tasks/:id` with `{"starred": false}` returns HTTP 200 with `starred: false`.
- **Completion Reset**:
  - Create a task, star it (`starred: true`), then call `POST /api/tasks/:id/complete`. Assert response contains `status: "done"`, `completedAt: not.toBeNull()`, and `starred: false`.
  - Query DB directly to verify `starred === 0`.
- **Query Filtering & Sorting**:
  - Create 3 tasks: Task 1 (unstarred, early), Task 2 (starred, middle), Task 3 (unstarred, late).
  - Verify default `GET /api/lists/:listId/tasks` returns `[Task 2, Task 3, Task 1]`.
  - Verify `GET /api/lists/:listId/tasks?starred=true` returns only Task 2.
  - Verify `GET /api/lists/:listId/tasks?starred=invalid` returns HTTP 400.

### 2. Frontend Component & Unit Tests
- `TaskRow.spec.tsx`:
  - Renders outline star button with accessible label `Star <task title>` for unstarred task.
  - Renders filled star button with accessible label `Unstar <task title>` for starred task.
  - Clicks trigger `onUpdate(task.id, { starred: true })` or `{ starred: false }`.
- `TaskList.spec.tsx`:
  - Validates that open tasks with `starred: true` render above unstarred open tasks regardless of raw array order.
- `FilterBar.spec.tsx`:
  - Verifies "Starred" chip renders and triggers `onChange({ ...filters, starred: true })`.

### 3. End-to-End Tests (`web/e2e/tasklist.spec.ts`)
- Add test `"stars and prioritizes tasks, then completes and unstars"`:
  1. Create task "Task A" then "Task B".
  2. Click star button on "Task A".
  3. Assert "Task A" moves above "Task B" in the list.
  4. Toggle "Starred" filter button: assert "Task A" is visible and "Task B" is hidden.
  5. Untoggle "Starred" filter.
  6. Click complete checkbox on "Task A".
  7. Expand "Done" accordion: verify "Task A" is in Done and unstarred.

## Rollout and operations

- **Zero-Downtime SQLite Schema Update**:
  - `PRAGMA table_info(tasks)` migration executes before handling HTTP requests during server startup (`server/src/db.ts`).
  - `ALTER TABLE tasks ADD COLUMN starred INTEGER NOT NULL DEFAULT 0 ...` is an instantaneous metadata-only operation in SQLite.
- **Rollback Strategy**:
  - If server code is rolled back, existing code executes `SELECT * FROM tasks`, ignoring the extra `starred` column without runtime failure.
- **Performance Impact**:
  - The composite index `idx_tasks_list_starred_created` prevents sequential table scans for list pagination and sorting.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Existing SQLite DB missing `starred` column crashes on startup | High | `PRAGMA table_info(tasks)` check in `db.ts` ensures `ALTER TABLE` runs idempotently only if the column does not exist. |
| Inconsistent serialization (SQLite `0`/`1` vs JS `boolean`) breaks frontend UI | Medium | Centralized `serializeTask` helper transforms all database outputs before sending JSON responses; verified via integration tests. |
| Race condition during optimistic star toggle and quick list refresh | Low | Optimistic state in `App.tsx` updates task immutably and re-sorts declaratively in `TaskList.tsx`; any API error triggers reconciliation via `load()`. |

## Open questions

1. **Reopening a completed task**:
   - *Question*: When a task is reopened via `POST /api/tasks/:id/reopen`, should it remain unstarred (`starred: false`), or should the system remember and restore its previous starred state?
   - *Specification Decision*: The task remains unstarred (`starred: false`). Storing historical pre-completion star status would require an additional column (e.g., `wasStarredBeforeCompletion`), which adds unnecessary schema complexity. Users can re-star the task after reopening if desired.
2. **Task creation with starred state**:
   - *Question*: Should `POST /api/lists/:listId/tasks` allow setting `starred: true` at creation time, or should tasks always be created unstarred and starred via `PATCH /api/tasks/:id`?
   - *Specification Decision*: Tasks are created with default `starred: false`. `createTaskSchema` does not include `starred`. Starring is performed via `PATCH /api/tasks/:id` or UI star toggle.
3. **Completed tasks starred badge**:
   - *Question*: When viewing the collapsible "Done" tasks section, should completed tasks that were previously starred retain any visual badge indicating they were starred prior to completion?
   - *Specification Decision*: No visual badge is retained. Completed tasks have `starred: 0` and are presented uniformly in the "Done" list.

## Story coverage

| Story | Sections |
|---|---|
| **TAS-12**: Database schema migration and Task model support for starred state | Context, Design > Components (Database Layer), Design > Data (Schema Definitions, Boot-Time Migration, Task Serialization), Test approach (Database & Server Integration Tests) |
| **TAS-13**: Starred task mutation and automatic reset on completion API | Design > Components (Server API Router), Design > Interfaces (REST API Endpoints), Design > Flows (Flow 1, Flow 2), Security and privacy, Test approach (Database & Server Integration Tests) |
| **TAS-14**: Starred task retrieval, query filtering, and prioritized sorting API | Design > Components (Server API Router, Web API Client), Design > Interfaces (REST API Endpoints, TypeScript Client), Design > Data (Schema Definitions), Test approach (Database & Server Integration Tests) |
| **TAS-15**: Star toggle control and prioritized visual list in TaskRow and TaskList | Design > Components (Web UI Components), Design > Interfaces (TypeScript Client & Component Signatures), Design > Flows (Flow 1), Test approach (Frontend Component & Unit Tests) |
| **TAS-16**: Starred filter bar toggle and end-to-end task starring lifecycle | Design > Components (Web UI Components), Design > Interfaces (TypeScript Client & Component Signatures), Design > Flows (Flow 3), Test approach (End-to-End Tests) |

## Sources

- [server/src/schema.sql](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/schema.sql)
- [server/src/db.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/db.ts)
- [server/src/routes/tasks.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/tasks.ts)
- [server/tests/tasks.test.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/tests/tasks.test.ts)
- [web/src/api/client.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/web/src/api/client.ts)
- [web/src/components/TaskRow.tsx](https://github.com/agentic-sdlc-demo/app-source/blob/main/web/src/components/TaskRow.tsx)
- [web/src/components/TaskList.tsx](https://github.com/agentic-sdlc-demo/app-source/blob/main/web/src/components/TaskList.tsx)
- [web/src/components/FilterBar.tsx](https://github.com/agentic-sdlc-demo/app-source/blob/main/web/src/components/FilterBar.tsx)
- [web/src/App.tsx](https://github.com/agentic-sdlc-demo/app-source/blob/main/web/src/App.tsx)
- [web/e2e/tasklist.spec.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/web/e2e/tasklist.spec.ts)
