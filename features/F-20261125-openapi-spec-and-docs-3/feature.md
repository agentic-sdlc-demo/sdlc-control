---
control_id: F-20261125-openapi-spec-and-docs-3
kind: feature
team: taskslist
drafted_by: shaheenks@shaheenks.altostrat.com
published: '2026-11-25T18:20:44Z'
---

# Feature: OpenAPI Specification and Interactive API Documentation

The tasklist backend currently validates request inputs with Zod and Express but lacks a machine-readable OpenAPI specification and an interactive documentation explorer. Backend and fullstack developers, frontend engineers, and automated test runners currently have no centralized, standardized contract for endpoints, request bodies, query parameters, and error responses. Delivering a code-first OpenAPI 3.1 document using `@asteasolutions/zod-to-openapi` and an embedded Swagger UI explorer at `/api/docs` provides a single source of truth for the API surface while serving pre-computed specifications from memory to avoid per-request parsing latency.

## Context and Problem Statement
The Express service under `server/src` manages lists and tasks with strict Zod validation schemas (`createListSchema`, `createTaskSchema`, `patchTaskSchema`) and standard error handling. However, there is no formal API specification, leading to drift between server implementations and client consumers. This feature introduces a code-first OpenAPI registry and interactive documentation UI conforming to the project's security baseline.

## User stories

### Schema registry for core models and standard error responses
As a Backend and Fullstack Developer, I want a code-first OpenAPI schema registry integrated with existing Zod schemas in `server/src/docs/registry.ts`, so that request, response, and error structures remain synchronized via automated route coverage tests.

Acceptance criteria:
- Given the OpenAPI schema registry in `server/src/docs/registry.ts` using `@asteasolutions/zod-to-openapi`, when registering standard error responses, then schemas define the nested envelope structure `{ error: { code: string, message: string } }` matching `errorHandler` in `server/src/middleware/errors.ts` for:
  - 400 `validation_error`
  - 404 `not_found`
  - 409 `already_done` / `already_open`
  - 429 `rate_limited`
  - 500 `internal_error`
- Given the task and list data models, when registering schema definitions, then `List`, `Task`, `createListSchema`, `createTaskSchema`, and `patchTaskSchema` are exported with field constraints and descriptions:
  - `List`: `id` (UUID), `name` (string 1-100 chars), `createdAt` (ISO-8601), `updatedAt` (ISO-8601).
  - `Task`: `id` (UUID), `listId` (UUID), `title` (string 1-200 chars), `status` ("open" | "done"), `priority` ("low" | "medium" | "high"), `dueDate` (string YYYY-MM-DD or null), `createdAt`, `updatedAt`, and `completedAt` (ISO-8601 or null).
- Given pagination query parameters, when registered, then schemas define `limit` (integer 1-200, default 50) and `offset` (integer >= 0, default 0).

### OpenAPI contract definitions for health and list endpoints
As a Frontend Engineer, I want explicit OpenAPI operation definitions for health and list routes, so that I have a reliable machine-readable contract for list creation and retrieval.

Acceptance criteria:
- Given the OpenAPI registry, when `GET /healthz` is documented, then it specifies a 200 response returning `{ status: "ok" }`.
- Given the `/api/lists` route in the registry:
  - `GET /api/lists` specifies `limit` and `offset` query parameters and a 200 response returning `{ items: List[], total: number }`.
  - `POST /api/lists` specifies a request body with `name` (1-100 characters), returning a 201 response with the created `List` object and a `Location` header (`/api/lists/{id}`).
  - Documented error responses include 400 `validation_error` and 429 `rate_limited`.

### OpenAPI contract definitions for task querying and mutation endpoints
As a Frontend Engineer, I want complete OpenAPI specifications for all task endpoints, so that task lifecycle actions, filtering options, and error scenarios are defined with query parameters, request bodies, and error response schemas.

Acceptance criteria:
- Given `GET /api/lists/{listId}/tasks` in the registry:
  - Documents path parameter `listId` (UUID).
  - Documents query parameters `status` ("open" | "done"), `priority` ("low" | "medium" | "high"), `dueBefore` (YYYY-MM-DD date string), `limit` (1-200), and `offset` (>= 0).
  - Documents 200 response returning `{ items: Task[], total: number }`, 400 `validation_error` (for invalid filter values), and 404 `not_found` (when list does not exist).
- Given `POST /api/lists/{listId}/tasks` in the registry:
  - Documents request body requiring `title` (1-200 chars), optional `priority` ("low" | "medium" | "high", default "medium"), and optional `dueDate` (regex `^\d{4}-\d{2}-\d{2}$`).
  - Documents 201 response with `Location` header (`/api/tasks/{id}`) returning the created `Task`, plus 400 `validation_error`, 404 `not_found`, and 429 `rate_limited`.
- Given `PATCH /api/tasks/{id}` in the registry:
  - Documents path parameter `id` and optional body fields `title` (1-200 chars), `priority` ("low" | "medium" | "high"), and `dueDate` (YYYY-MM-DD or null), with constraint requiring at least one field.
  - Documents 200 response with updated `Task`, 400 `validation_error`, 404 `not_found`, and 429 `rate_limited`.
- Given `DELETE /api/tasks/{id}` in the registry:
  - Documents path parameter `id`, 204 response on success, 404 `not_found`, and 429 `rate_limited`.
- Given task transition routes `POST /api/tasks/{id}/complete` and `POST /api/tasks/{id}/reopen`:
  - Document 200 response with updated `Task`, 404 `not_found`, 409 conflict (`already_done` or `already_open`), and 429 `rate_limited`.

### Serve cached OpenAPI 3.1 specification at /api/openapi.json
As an Automated API test runner, I want to fetch the complete OpenAPI 3.1 document via HTTP at `/api/openapi.json`, so that downstream tools and clients can ingest the current API contract.

Acceptance criteria:
- Given an initialized Express application, when requesting `GET /api/openapi.json`, then the server returns HTTP 200 with `Content-Type: application/json`.
- Given the response from `GET /api/openapi.json`, then the document specifies `openapi: 3.1.0` and contains metadata (`title: \"Tasklist API\"`, `version: \"1.0.0\"`), servers, components, and all documented paths.
- Given `server/src/docs/openapi.ts`, the specification is built once upon module initialization and served directly from memory.
- Given response headers on `GET /api/openapi.json`, `Cache-Control: public, max-age=3600` is returned along with security headers (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`).

### Interactive documentation UI at /api/docs compliant with Content Security Policy
As a Backend and Fullstack Developer, I want an interactive documentation interface served at `/api/docs`, so that I can explore and test endpoints in a browser without violating Content Security Policy (CSP).

Acceptance criteria:
- Given a running server, when navigating to `GET /api/docs` or `GET /api/docs/`, then the server responds with HTTP 200 serving Swagger UI.
- Given `server/src/routes/docs.ts`, assets from `swagger-ui-dist` are served statically from local node_modules without external CDN requests.
- Given the global CSP in `server/src/app.ts` (`default-src 'self'`), a route-scoped middleware for `/api/docs` overrides CSP to permit Swagger UI inline styles (`style-src 'self' 'unsafe-inline'`) while keeping script and connect sources restricted to `'self'`.
- Given a browser loading `/api/docs`, the page initializes and fetches `/api/openapi.json` without CSP or console errors.

### Automated test suite for OpenAPI schema validity and route coverage
As an Automated API test runner, I want automated Vitest tests validating the OpenAPI specification and route coverage, so that regressions in endpoints or documentation contracts are caught in CI.

Acceptance criteria:
- Given `server/tests/openapi.test.ts`, when executed with Vitest, then the generated document is validated using `@apidevtools/swagger-parser` against the OpenAPI specification without errors.
- Given the test suite, all non-meta API paths (`/api/lists`, `/api/lists/:listId/tasks`, `/api/tasks/:id`, `/api/tasks/:id/complete`, `/api/tasks/:id/reopen`) and `/healthz` are verified to exist in the OpenAPI document with corresponding HTTP methods.
- Given `GET /api/docs`, the test verifies an HTTP 200 response with `Content-Type: text/html`.

## Out of scope
- Documenting internal `/metrics` endpoint.
- Automated client SDK generation tooling and npm package publishing.
- External OAuth/JWT authentication schemes.
- UI custom themes beyond standard styling conforming to existing CSP.

## Architectural Design & File Layout
- `server/src/docs/registry.ts`: `@asteasolutions/zod-to-openapi` registry defining schemas and endpoints.
- `server/src/docs/openapi.ts`: Generates and exports the pre-computed OpenAPI 3.1 JSON document.
- `server/src/routes/docs.ts`: Mounts `/api/openapi.json` and Swagger UI static middleware on `/api/docs` with route-level CSP header customization.
- `server/tests/openapi.test.ts`: Vitest test suite testing spec schema validity and endpoint coverage.

## Sources
- [server/src/app.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/app.ts)
- [server/src/routes/lists.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/lists.ts)
- [server/src/routes/tasks.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/tasks.ts)
- [server/src/routes/health.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/health.ts)
- [server/src/middleware/errors.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/middleware/errors.ts)
- [server/src/middleware/validate.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/middleware/validate.ts)
- [server/package.json](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/package.json)
- [server/tests/validation.test.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/tests/validation.test.ts)
