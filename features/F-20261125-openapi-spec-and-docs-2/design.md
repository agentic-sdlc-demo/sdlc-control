---
control_id: F-20261125-openapi-spec-and-docs-2
kind: design
team: taskslist
drafted_by: shaheenks@shaheenks.altostrat.com
published: '2026-11-25T18:27:12Z'
previous:
  path: features/F-20261125-openapi-spec-and-docs-2/feature.md
  commit: 8688a611d56c8225243d772a1e7a2d9ea42cf227
  approved: true
---

# TAS-OPENAPI: OpenAPI Specification and Interactive API Documentation

| | |
|---|---|
| Feature | TAS-OPENAPI |
| Stories | TAS-STORY-1, TAS-STORY-2, TAS-STORY-3, TAS-STORY-4, TAS-STORY-5, TAS-STORY-6 |
| Target repositories | agentic-sdlc-demo/app-source (pull request) |
| Status | Draft |

## Context

The Tasklist backend is an Express service running on Node.js 20 with SQLite (`better-sqlite3`). Request payloads are validated at runtime using Zod schemas (`createListSchema`, `createTaskSchema`, `patchTaskSchema`), and API responses follow the standard error envelope `{ error: { code: string, message: string } }` defined in `server/src/middleware/errors.ts`.

However, the service lacks a machine-readable OpenAPI specification and an interactive documentation explorer. Without a centralized, standardized contract, client consumers (frontend components, automated test suites, and third-party integrations) face contract drift. Manual OpenAPI definitions tend to desynchronize from runtime code over time.

To maintain single-source-of-truth parity, this design introduces a code-first OpenAPI 3.1 registry using `@asteasolutions/zod-to-openapi`. The OpenAPI specification is pre-computed in memory upon server boot to eliminate runtime generation overhead, and an embedded Swagger UI interface is served at `/api/docs` from local package assets (`swagger-ui-dist`) while strictly maintaining compliance with the project's Content Security Policy (CSP).

## Goals

- Establish a code-first OpenAPI 3.1 schema registry in `server/src/docs/registry.ts` backed by `@asteasolutions/zod-to-openapi` that exports core entity schemas (`List`, `Task`), mutation schemas (`createListSchema`, `createTaskSchema`, `patchTaskSchema`), query/pagination parameters, and standard error envelopes.
- Maintain a single source of truth for schema validation by having route handlers in `server/src/routes/lists.ts` and `server/src/routes/tasks.ts` import their validation schemas directly from `server/src/docs/registry.ts`.
- Register all public API operations via `registry.registerPath(...)`: health check (`GET /healthz`), list operations (`GET /api/lists`, `POST /api/lists`), and task lifecycle operations (`GET /api/lists/{listId}/tasks`, `POST /api/lists/{listId}/tasks`, `PATCH /api/tasks/{id}`, `DELETE /api/tasks/{id}`, `POST /api/tasks/{id}/complete`, `POST /api/tasks/{id}/reopen`).
- Pre-compute and cache the complete OpenAPI 3.1 JSON document in memory upon server initialization and serve it at `GET /api/openapi.json` with `Cache-Control: public, max-age=3600` and security headers.
- Serve interactive Swagger UI documentation at `/api/docs`, `/api/docs/`, and `/api/docs/index.html` using local `swagger-ui-dist` assets with route-scoped CSP adjustments (`style-src 'self' 'unsafe-inline'`, `img-src 'self' data:`) while disabling static default index pages (`{ index: false }`) and preserving `script-src 'self'` and `connect-src 'self'`.
- Provide automated CI test coverage in `server/tests/openapi.test.ts` verifying OpenAPI 3.1 schema validity via `@apidevtools/swagger-parser` and asserting complete route and method coverage for all registered endpoints.

## Non-goals

- Documenting the internal `/metrics` endpoint (reserved for internal monitoring and scraping).
- Automated client SDK generation, code-generation pipelines, or publishing npm client packages.
- Adding external OAuth2, OpenID Connect, or JWT authentication schemes (the service currently operates on a single implicit local user model).
- Custom Swagger UI brand themes beyond standard styling conforming to existing project CSP rules.
- Generating OpenAPI documentation dynamically at runtime per HTTP request.

## Design

### Components

The architecture integrates four main components within the existing `server` workspace:

```
server/
  src/
    docs/
      registry.ts        # OpenAPIRegistry: schemas, components, and route definitions
      openapi.ts         # Pre-computed OpenAPI 3.1 JSON document generator & memory cache
    routes/
      docs.ts            # Router mounting /api/openapi.json and /api/docs Swagger UI handler
    app.ts               # Express assembly: mounts docsRouter at root before catch-all routes
  tests/
    openapi.test.ts      # Vitest suite: SwaggerParser validation and route coverage
```

#### 1. Schema & Route Registry (`server/src/docs/registry.ts`)
- Imports `extendZodWithOpenApi` from `@asteasolutions/zod-to-openapi` and extends the global `z` instance once.
- Instantiates an `OpenAPIRegistry` instance.
- Defines, registers, and exports shared schema definitions:
  - Standard error envelope and specific error responses: `ValidationError` (400), `NotFoundError` (404), `ConflictError` (409), `RateLimitedError` (429), `InternalError` (500).
  - Core data models: `List`, `Task`.
  - Request body validation schemas: `createListSchema`, `createTaskSchema`, `patchTaskSchema`. To preserve the single-source-of-truth principle and prevent contract drift, route handlers in `server/src/routes/lists.ts` and `server/src/routes/tasks.ts` import these schemas directly from `registry.ts` instead of duplicating them.
  - Query parameter schemas: `limitQuerySchema`, `offsetQuerySchema`, `statusQuerySchema`, `priorityQuerySchema`, and `dueBeforeQuerySchema`.
- Registers paths for all public routes using `registry.registerPath(...)` with explicit parameter schemas, request bodies, and response contracts. For example, route registration for `GET /api/lists` and `POST /api/lists`:

```typescript
registry.registerPath({
  method: "get",
  path: "/api/lists",
  summary: "Get lists",
  description: "Retrieve paginated lists",
  request: {
    query: z.object({
      limit: limitQuerySchema.optional(),
      offset: offsetQuerySchema.optional(),
    }),
  },
  responses: {
    200: {
      description: "Paginated lists",
      content: {
        "application/json": {
          schema: z.object({
            items: z.array(ListSchema),
            total: z.number().int().nonnegative(),
          }),
        },
      },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});
```

#### 2. Specification Generator (`server/src/docs/openapi.ts`)
- Uses `OpenApiGeneratorV31` from `@asteasolutions/zod-to-openapi` to compile the registry definitions into an OpenAPI 3.1.0 document.
- Injected metadata:
  - `openapi`: `"3.1.0"`
  - `info`: `{ title: "Tasklist API", version: "1.0.0", description: "Tasklist REST API service" }`
  - `servers`: `[{ url: "/", description: "Current environment" }]`
- Evaluated once upon module import and stored in an immutable module-level constant (`export const openApiDocument = ...;`).
- Serialized to a JSON buffer/string once (`export const openApiJson = JSON.stringify(openApiDocument);`) to eliminate per-request JSON serialization cost.

#### 3. Documentation Router (`server/src/routes/docs.ts`)
- Mounts routes on an Express router:
  - `GET /api/openapi.json`: Responds with HTTP 200, `Content-Type: application/json`, `Cache-Control: public, max-age=3600`, and security headers.
  - `GET /api/docs`, `GET /api/docs/`, and `GET /api/docs/index.html`: Serves the HTML shell loading Swagger UI. Explicitly handling `/api/docs/index.html` prevents requests from bypassing custom CSP headers and serving pre-packaged index pages.
  - `GET /api/docs/swagger-initializer.js`: Serves the external script initializing Swagger UI pointing to `/api/openapi.json`.
  - Static middleware `express.static(swaggerUiDist.getAbsoluteFSPath(), { index: false })` scoped to `/api/docs` to serve static assets (`swagger-ui.css`, `swagger-ui-bundle.js`, `swagger-ui-standalone-preset.js`, icons) locally from `node_modules/swagger-ui-dist` with default index serving disabled.
- Route-scoped CSP middleware: Overrides the global CSP header for `/api/docs` requests:
  `Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; script-src 'self'; connect-src 'self'`

#### 4. Express App Integration (`server/src/app.ts`)
- Mounts `docsRouter` on the Express application at the root level using `app.use(docsRouter)`. Because the internal endpoints in `docsRouter` are already prefixed with `/api` (e.g., `/api/openapi.json`, `/api/docs`), mounting at root ensures endpoints resolve correctly to `/api/docs` and `/api/openapi.json` without incorrect `/api/api/...` double-prefixing.
- Placed alongside existing routers (`healthRouter`, `listsRouter`, `tasksRouter`) and strictly before the SPA catch-all middleware (`app.get(/^(?!\/api).*/, ...)`), ensuring `/api/docs` and `/api/openapi.json` are not captured by the web client fallback.

### Interfaces

#### Dependency Additions (`server/package.json`)
- Runtime dependencies:
  - `@asteasolutions/zod-to-openapi`: `^7.1.2`
  - `swagger-ui-dist`: `^5.17.14`
- Development dependencies:
  - `@apidevtools/swagger-parser`: `^10.1.0`
  - `@types/swagger-ui-dist`: `^3.35.9`

#### Registry Module (`server/src/docs/registry.ts`)
```typescript
import { extendZodWithOpenApi, OpenAPIRegistry } from "@asteasolutions/zod-to-openapi";
import { z } from "zod";

extendZodWithOpenApi(z);

export const registry = new OpenAPIRegistry();

// Error response schemas
export const errorEnvelopeSchema = (codeExample: string, messageExample: string) =>
  z.object({
    error: z.object({
      code: z.string().openapi({ example: codeExample }),
      message: z.string().openapi({ example: messageExample }),
    }),
  }).openapi({ description: `Error envelope for ${codeExample}` });

export const ValidationErrorSchema = registry.register(
  "ValidationError",
  errorEnvelopeSchema("validation_error", "title: Required")
);

export const NotFoundErrorSchema = registry.register(
  "NotFoundError",
  errorEnvelopeSchema("not_found", "Resource not found")
);

export const ConflictErrorSchema = registry.register(
  "ConflictError",
  errorEnvelopeSchema("already_done", "Task is already complete")
);

export const RateLimitedErrorSchema = registry.register(
  "RateLimitedError",
  errorEnvelopeSchema("rate_limited", "Too many requests — try again shortly")
);

export const InternalErrorSchema = registry.register(
  "InternalError",
  errorEnvelopeSchema("internal_error", "Something went wrong")
);

// Query parameter schemas
export const limitQuerySchema = z.coerce
  .number()
  .int()
  .min(1)
  .max(200)
  .default(50)
  .openapi({ description: "Number of items to return (1-200)", example: 50 });

export const offsetQuerySchema = z.coerce
  .number()
  .int()
  .min(0)
  .default(0)
  .openapi({ description: "Number of items to skip (>= 0)", example: 0 });

export const statusQuerySchema = z
  .enum(["open", "done"])
  .openapi({ description: "Filter tasks by status", example: "open" });

export const priorityQuerySchema = z
  .enum(["low", "medium", "high"])
  .openapi({ description: "Filter tasks by priority", example: "medium" });

export const dueBeforeQuerySchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .openapi({ description: "Filter tasks due on or before date (YYYY-MM-DD)", example: "2026-05-01" });

// Core Model schemas
export const ListSchema = registry.register(
  "List",
  z.object({
    id: z.string().uuid().openapi({ description: "Unique list identifier (UUID)", example: "123e4567-e89b-12d3-a456-426614174000" }),
    name: z.string().min(1).max(100).openapi({ description: "List name", example: "Groceries" }),
    createdAt: z.string().datetime().openapi({ description: "ISO-8601 creation timestamp", example: "2026-03-30T12:00:00.000Z" }),
    updatedAt: z.string().datetime().openapi({ description: "ISO-8601 last update timestamp", example: "2026-03-30T12:00:00.000Z" }),
  })
);

export const TaskSchema = registry.register(
  "Task",
  z.object({
    id: z.string().uuid().openapi({ description: "Unique task identifier (UUID)", example: "987fcdeb-51a2-43f7-9abc-def012345678" }),
    listId: z.string().uuid().openapi({ description: "Parent list identifier (UUID)", example: "123e4567-e89b-12d3-a456-426614174000" }),
    title: z.string().min(1).max(200).openapi({ description: "Task title", example: "Buy milk" }),
    status: z.enum(["open", "done"]).openapi({ description: "Task completion status", example: "open" }),
    priority: z.enum(["low", "medium", "high"]).openapi({ description: "Task priority", example: "medium" }),
    dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().openapi({ description: "Due date in YYYY-MM-DD format or null", example: "2026-04-15" }),
    createdAt: z.string().datetime().openapi({ description: "ISO-8601 creation timestamp", example: "2026-03-30T12:00:00.000Z" }),
    updatedAt: z.string().datetime().openapi({ description: "ISO-8601 last update timestamp", example: "2026-03-30T12:00:00.000Z" }),
    completedAt: z.string().datetime().nullable().openapi({ description: "ISO-8601 completion timestamp or null", example: null }),
  })
);

// Shared Request Validation Schemas (Imported by server/src/routes/lists.ts and server/src/routes/tasks.ts)
export const createListSchema = registry.register(
  "CreateListInput",
  z.object({
    name: z.string().trim().min(1).max(100).openapi({ description: "List name (1-100 characters)", example: "Home Improvement" }),
  }).strict()
);

export const createTaskSchema = registry.register(
  "CreateTaskInput",
  z.object({
    title: z.string().trim().min(1).max(200).openapi({ description: "Task title (1-200 characters)", example: "Paint the front door" }),
    priority: z.enum(["low", "medium", "high"]).optional().default("medium").openapi({ description: "Priority level", example: "medium" }),
    dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().openapi({ description: "ISO-8601 date string (YYYY-MM-DD)", example: "2026-05-01" }),
  }).strict()
);

export const patchTaskSchema = registry.register(
  "PatchTaskInput",
  z.object({
    title: z.string().trim().min(1).max(200).optional().openapi({ description: "Updated task title", example: "Paint the front door blue" }),
    priority: z.enum(["low", "medium", "high"]).optional().openapi({ description: "Updated priority", example: "high" }),
    dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional().openapi({ description: "Updated due date (YYYY-MM-DD) or null to clear", example: "2026-05-10" }),
  }).strict().refine((obj) => Object.keys(obj).length > 0, { message: "at least one field required" })
);

// Route Path Registrations

// 1. GET /healthz
registry.registerPath({
  method: "get",
  path: "/healthz",
  summary: "Health check",
  description: "Check if the service is alive and healthy",
  responses: {
    200: {
      description: "Service is healthy",
      content: {
        "application/json": {
          schema: z.object({ status: z.string().openapi({ example: "ok" }) }),
        },
      },
    },
  },
});

// 2. GET /api/lists
registry.registerPath({
  method: "get",
  path: "/api/lists",
  summary: "List all lists",
  description: "Retrieve paginated lists",
  request: {
    query: z.object({
      limit: limitQuerySchema.optional(),
      offset: offsetQuerySchema.optional(),
    }),
  },
  responses: {
    200: {
      description: "Paginated lists",
      content: {
        "application/json": {
          schema: z.object({
            items: z.array(ListSchema),
            total: z.number().int().nonnegative().openapi({ example: 1 }),
          }),
        },
      },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 3. POST /api/lists
registry.registerPath({
  method: "post",
  path: "/api/lists",
  summary: "Create list",
  description: "Create a new list",
  request: {
    body: {
      content: {
        "application/json": {
          schema: createListSchema,
        },
      },
    },
  },
  responses: {
    201: {
      description: "List created",
      headers: {
        Location: {
          schema: { type: "string" },
          description: "URI of the newly created list",
        },
      },
      content: {
        "application/json": { schema: ListSchema },
      },
    },
    400: {
      description: "Bad Request",
      content: { "application/json": { schema: ValidationErrorSchema } },
    },
    429: {
      description: "Too Many Requests",
      content: { "application/json": { schema: RateLimitedErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 4. GET /api/lists/{listId}/tasks
registry.registerPath({
  method: "get",
  path: "/api/lists/{listId}/tasks",
  summary: "Get tasks in list",
  description: "Query tasks belonging to a list with optional filters",
  request: {
    params: z.object({
      listId: z.string().uuid().openapi({ description: "Parent list identifier", example: "123e4567-e89b-12d3-a456-426614174000" }),
    }),
    query: z.object({
      status: statusQuerySchema.optional(),
      priority: priorityQuerySchema.optional(),
      dueBefore: dueBeforeQuerySchema.optional(),
      limit: limitQuerySchema.optional(),
      offset: offsetQuerySchema.optional(),
    }),
  },
  responses: {
    200: {
      description: "Paginated list tasks",
      content: {
        "application/json": {
          schema: z.object({
            items: z.array(TaskSchema),
            total: z.number().int().nonnegative().openapi({ example: 1 }),
          }),
        },
      },
    },
    400: {
      description: "Bad Request",
      content: { "application/json": { schema: ValidationErrorSchema } },
    },
    404: {
      description: "Not Found",
      content: { "application/json": { schema: NotFoundErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 5. POST /api/lists/{listId}/tasks
registry.registerPath({
  method: "post",
  path: "/api/lists/{listId}/tasks",
  summary: "Create task",
  description: "Create a new task within a specified list",
  request: {
    params: z.object({
      listId: z.string().uuid().openapi({ description: "Parent list identifier", example: "123e4567-e89b-12d3-a456-426614174000" }),
    }),
    body: {
      content: {
        "application/json": {
          schema: createTaskSchema,
        },
      },
    },
  },
  responses: {
    201: {
      description: "Task created",
      headers: {
        Location: {
          schema: { type: "string" },
          description: "URI of the newly created task",
        },
      },
      content: {
        "application/json": { schema: TaskSchema },
      },
    },
    400: {
      description: "Bad Request",
      content: { "application/json": { schema: ValidationErrorSchema } },
    },
    404: {
      description: "Not Found",
      content: { "application/json": { schema: NotFoundErrorSchema } },
    },
    429: {
      description: "Too Many Requests",
      content: { "application/json": { schema: RateLimitedErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 6. PATCH /api/tasks/{id}
registry.registerPath({
  method: "patch",
  path: "/api/tasks/{id}",
  summary: "Update task",
  description: "Partially update task fields",
  request: {
    params: z.object({
      id: z.string().uuid().openapi({ description: "Task identifier", example: "987fcdeb-51a2-43f7-9abc-def012345678" }),
    }),
    body: {
      content: {
        "application/json": {
          schema: patchTaskSchema,
        },
      },
    },
  },
  responses: {
    200: {
      description: "Task updated",
      content: { "application/json": { schema: TaskSchema } },
    },
    400: {
      description: "Bad Request",
      content: { "application/json": { schema: ValidationErrorSchema } },
    },
    404: {
      description: "Not Found",
      content: { "application/json": { schema: NotFoundErrorSchema } },
    },
    429: {
      description: "Too Many Requests",
      content: { "application/json": { schema: RateLimitedErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 7. DELETE /api/tasks/{id}
registry.registerPath({
  method: "delete",
  path: "/api/tasks/{id}",
  summary: "Delete task",
  description: "Permanently delete a task",
  request: {
    params: z.object({
      id: z.string().uuid().openapi({ description: "Task identifier", example: "987fcdeb-51a2-43f7-9abc-def012345678" }),
    }),
  },
  responses: {
    204: {
      description: "Task deleted",
    },
    404: {
      description: "Not Found",
      content: { "application/json": { schema: NotFoundErrorSchema } },
    },
    429: {
      description: "Too Many Requests",
      content: { "application/json": { schema: RateLimitedErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 8. POST /api/tasks/{id}/complete
registry.registerPath({
  method: "post",
  path: "/api/tasks/{id}/complete",
  summary: "Complete task",
  description: "Mark a task as completed",
  request: {
    params: z.object({
      id: z.string().uuid().openapi({ description: "Task identifier", example: "987fcdeb-51a2-43f7-9abc-def012345678" }),
    }),
  },
  responses: {
    200: {
      description: "Task completed",
      content: { "application/json": { schema: TaskSchema } },
    },
    404: {
      description: "Not Found",
      content: { "application/json": { schema: NotFoundErrorSchema } },
    },
    409: {
      description: "Conflict - Task already completed",
      content: { "application/json": { schema: ConflictErrorSchema } },
    },
    429: {
      description: "Too Many Requests",
      content: { "application/json": { schema: RateLimitedErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});

// 9. POST /api/tasks/{id}/reopen
registry.registerPath({
  method: "post",
  path: "/api/tasks/{id}/reopen",
  summary: "Reopen task",
  description: "Reopen a completed task",
  request: {
    params: z.object({
      id: z.string().uuid().openapi({ description: "Task identifier", example: "987fcdeb-51a2-43f7-9abc-def012345678" }),
    }),
  },
  responses: {
    200: {
      description: "Task reopened",
      content: { "application/json": { schema: TaskSchema } },
    },
    404: {
      description: "Not Found",
      content: { "application/json": { schema: NotFoundErrorSchema } },
    },
    409: {
      description: "Conflict - Task already open",
      content: { "application/json": { schema: ConflictErrorSchema } },
    },
    429: {
      description: "Too Many Requests",
      content: { "application/json": { schema: RateLimitedErrorSchema } },
    },
    500: {
      description: "Internal Server Error",
      content: { "application/json": { schema: InternalErrorSchema } },
    },
  },
});
