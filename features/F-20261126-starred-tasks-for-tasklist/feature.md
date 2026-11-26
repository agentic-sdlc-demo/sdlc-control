---
control_id: F-20261126-starred-tasks-for-tasklist
team: taskslist
kind: feature
drafted_by: shaheenks@shaheenks.altostrat.com
approved_by: shaheenks@shaheenks.altostrat.com
approved_at: '2026-11-26T13:07:28Z'
approved_in: chat
---

# Feature: Starred Tasks for Tasklist

Users managing tasks in the Tasklist web application struggle to distinguish critical or urgent items in chronological lists. End users need an intuitive way to mark tasks as starred so they remain prominently pinned to the top of their list and easily filterable. This feature adds full-stack support for starring tasks, including SQLite schema migration, PATCH and completion API handling, top-of-list sorting, and interactive UI toggles. It originates from the [Starred Tasks for Tasklist Brief](#brief).

High-level estimate: S (about 1 to 2 weeks for one fullstack engineer): driven by schema migration safety on SQLite, synchronous reset logic on task completion, and optimistic UI star toggling with list reordering.

## User stories

### Database schema migration and Task model support for starred state
As an End user, I want the task database to persist a starred status for each task, so that my starred selections are preserved across application restarts.

Story points: 2 (Straightforward SQLite column addition with backwards compatibility and default zero value; low risk).

Acceptance criteria:
- Given an existing SQLite database initialized from `server/src/schema.sql`, when migration runs at boot in `server/src/db.ts`, then the `tasks` table includes a `starred` column defined as `INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0, 1))`.
- Given tasks existing prior to migration, when queried from SQLite, then all existing records have `starred` equal to `0`.
- Given `server/src/routes/tasks.ts`, when a task is serialized for JSON response, then the `starred` attribute is returned as a boolean (`true` or `false`).

### Starred task mutation and automatic reset on completion API
As an End user, I want to star or unstar a task via the API and have completion automatically clear the star, so that resolved tasks do not clutter my prioritized tasks.

Story points: 3 (Extending Zod validation schema in `patchTaskSchema`, updating PATCH handler parameterized queries, and resetting starred state in `POST /api/tasks/:id/complete`).

Acceptance criteria:
- Given `PATCH /api/tasks/:id` with payload `{"starred": true}`, when the request is sent, then the server responds with HTTP 200 and the updated task has `starred: true`.
- Given `PATCH /api/tasks/:id` with payload `{"starred": "yes"}`, when validated by Zod, then the server responds with HTTP 400 and error code `validation_error`.
- Given a task with `starred: true`, when `POST /api/tasks/:id/complete` is executed, then the server responds with HTTP 200 and the task has `status: "done"`, `completedAt` populated, and `starred: false`.
- Given a task with `starred: false`, when `POST /api/tasks/:id/complete` is executed, then the task is marked done with `starred: false`.

### Starred task retrieval, query filtering, and prioritized sorting API
As an End user, I want task list queries to prioritize starred items and filter for starred tasks only, so that I can immediately view my high-priority items.

Story points: 3 (Modifying SQL query builder in `server/src/routes/tasks.ts` to sort by `starred DESC, createdAt DESC` and support optional `?starred=true` filter parameter).

Acceptance criteria:
- Given multiple open tasks where some are starred and some unstarred, when `GET /api/lists/:listId/tasks` is called without explicit sort parameters, then returned items are ordered with starred tasks first, followed by unstarred tasks ordered by `createdAt DESC`.
- Given `GET /api/lists/:listId/tasks?starred=true`, when requested, then the server returns HTTP 200 containing only tasks where `starred` is true.
- Given `GET /api/lists/:listId/tasks?starred=invalid`, when requested, then the server returns HTTP 400 with error code `validation_error`.
- Given `web/src/api/client.ts`, when invoking `listTasks` and `updateTask`, then TypeScript definitions include `starred: boolean` and `TaskFilters` accepts `starred?: boolean`.

### Star toggle control and prioritized visual list in TaskRow and TaskList
As an End user, I want a clickable star icon on each task row that pins starred tasks to the top, so that I can highlight and see important tasks first.

Story points: 3 (UI component updates in `TaskRow.tsx` and `TaskList.tsx`, adding accessible star button, visual styling, and optimistic ordering in UI state).

Acceptance criteria:
- Given an unstarred task row in `TaskRow.tsx`, when rendered, then it displays an outline star button with accessible label `Star <task title>`.
- Given a user clicks the star button on an unstarred task, when the action triggers, then the star updates to a filled highlight icon within 100ms and invokes `onUpdate(task.id, { starred: true })`.
- Given a list of open tasks in `TaskList.tsx`, when one or more tasks are starred, then all starred open tasks are displayed above unstarred open tasks in the list.
- Given a user clicks the star button on an already starred task, when the action triggers, then the star icon reverts to outline and invokes `onUpdate(task.id, { starred: false })`.

### Starred filter bar toggle and end-to-end task starring lifecycle
As an End user, I want a "Starred" filter chip in the filter bar, so that I can isolate only my starred tasks and verify the entire lifecycle from starring to completion.

Story points: 3 (State management integration in `App.tsx`, filter button addition in `FilterBar.tsx`, and Playwright E2E coverage).

Acceptance criteria:
- Given `FilterBar.tsx`, when rendered, then a "Starred" filter chip is displayed alongside existing status and priority filter buttons.
- Given the "Starred" filter chip is toggled on, when the task list updates, then only tasks with `starred === true` are visible in the task list.
- Given an open starred task, when the user clicks the task completion checkbox, then the task status changes to "done" and its starred state is reset to unstarred.
- Given the Playwright test suite `web/e2e/tasklist.spec.ts`, when the starring lifecycle test runs, then it successfully creates a task, stars it, asserts it reorders above older tasks, and verifies completing it clears the star.

## Jira
- Proposed epic: Task Prioritization and Organization: Capabilities for users to highlight, organize, and prioritize key tasks in Tasklist
- Extends open feature: none
- Possible duplicate stories: none

## Out of scope
- Manual drag-and-drop reordering of tasks within starred or unstarred sections.
- Multi-tier priority stars (e.g., 1 to 5 star rating system) or custom star colors.
- Starred task push notifications, email alerts, or due-date reminder integrations.
- Starring or favoriting entire task lists.

## Open questions
- When a completed task is reopened via `POST /api/tasks/:id/reopen`, should it remain unstarred (`starred: false`), or should the system remember and restore its previous starred state?
- Should `POST /api/lists/:listId/tasks` allow setting `starred: true` at creation time, or should tasks always be created unstarred and starred via `PATCH /api/tasks/:id`?
- When viewing the collapsible "Done" tasks section, should completed tasks that were previously starred retain any visual badge indicating they were starred prior to completion?

## Sources
- [server/src/schema.sql](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [server/src/db.ts](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [server/src/routes/tasks.ts](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [web/src/api/client.ts](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [web/src/components/TaskRow.tsx](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [web/src/components/TaskList.tsx](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [web/src/components/FilterBar.tsx](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [web/src/App.tsx](https://github.com/agentic-sdlc-demo/app-source/tree/main)
- [server/tests/tasks.test.ts](https://github.com/agentic-sdlc-demo/app-source/tree/main)
