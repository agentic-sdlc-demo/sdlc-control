---
control_id: F-20261125-openapi-specification-and-interactive-ap
kind: design
team: taskslist
drafted_by: shaheenks@shaheenks.altostrat.com
published: '2026-11-25T18:16:01Z'
previous:
  path: features/F-20261125-openapi-specification-and-interactive-ap/feature.md
  in_this_pull_request: true
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
```

#### Document Generator Module (`server/src/docs/openapi.ts`)
```typescript
import { OpenApiGeneratorV31 } from "@asteasolutions/zod-to-openapi";
import { registry } from "./registry";

const generator = new OpenApiGeneratorV31(registry.definitions);

export const openApiDocument = generator.generateDocument({
  openapi: "3.1.0",
  info: {
    title: "Tasklist API",
    version: "1.0.0",
    description: "REST API for managing lists and tasks",
  },
  servers: [
    {
      url: "/",
      description: "Default server root",
    },
  ],
});

export const openApiJson = JSON.stringify(openApiDocument, null, 2);
```

#### Documentation Router (`server/src/routes/docs.ts`)
```typescript
import { Router, Request, Response, NextFunction } from "express";
import express from "express";
import swaggerUiDist from "swagger-ui-dist";
import { openApiJson } from "../docs/openapi";

export const docsRouter = Router();

// Route-scoped Content Security Policy middleware for Swagger UI
function docsCspMiddleware(_req: Request, res: Response, next: NextFunction): void {
  res.setHeader(
    "Content-Security-Policy",
    "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; script-src 'self'; connect-src 'self'"
  );
  next();
}

// 1. Raw OpenAPI 3.1 Specification JSON
docsRouter.get("/api/openapi.json", (_req: Request, res: Response) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "public, max-age=3600");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.status(200).send(openApiJson);
});

// 2. Custom Swagger Initializer Script (avoids inline script in HTML to satisfy script-src 'self')
docsRouter.get("/api/docs/swagger-initializer.js", docsCspMiddleware, (_req: Request, res: Response) => {
  res.setHeader("Content-Type", "application/javascript");
  res.send(`
    window.onload = function() {
      window.ui = SwaggerUIBundle({
        url: "/api/openapi.json",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        plugins: [
          SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "StandaloneLayout"
      });
    };
  `);
});

// 3. Swagger UI HTML page (matched on /api/docs, /api/docs/, and /api/docs/index.html)
const swaggerHtml = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>Tasklist API Documentation</title>
    <link rel="stylesheet" type="text/css" href="/api/docs/swagger-ui.css" />
    <link rel="icon" type="image/png" href="/api/docs/favicon-32x32.png" sizes="32x32" />
    <link rel="icon" type="image/png" href="/api/docs/favicon-16x16.png" sizes="16x16" />
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="/api/docs/swagger-ui-bundle.js" charset="UTF-8"></script>
    <script src="/api/docs/swagger-ui-standalone-preset.js" charset="UTF-8"></script>
    <script src="/api/docs/swagger-initializer.js" charset="UTF-8"></script>
  </body>
</html>`;

docsRouter.get(["/api/docs", "/api/docs/", "/api/docs/index.html"], docsCspMiddleware, (_req: Request, res: Response) => {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(200).send(swaggerHtml);
});

// 4. Static assets from swagger-ui-dist (with index: false to prevent serving default non-CSP index.html)
docsRouter.use(
  "/api/docs",
  docsCspMiddleware,
  express.static(swaggerUiDist.getAbsoluteFSPath(), { index: false })
);
```

#### OpenAPI Registered Endpoints and HTTP Contracts

1. **`GET /healthz`**
   - Description: Service health verification check.
   - Response: `200 OK`
     - Content-Type: `application/json`
     - Body: `{ status: "ok" }`

2. **`GET /api/lists`**
   - Description: Retrieve paginated lists.
   - Query Parameters:
     - `limit` (integer, optional, default: 50, min: 1, max: 200)
     - `offset` (integer, optional, default: 0, min: 0)
   - Responses:
     - `200 OK`: `{ items: List[], total: number }`
     - `500 Internal Server Error`: `InternalError`

3. **`POST /api/lists`**
   - Description: Create a new list.
   - Request Body: `application/json` -> `CreateListInput` (`{ name: string }`)
   - Responses:
     - `201 Created`: `List` object. Header: `Location: /api/lists/{id}`
     - `400 Bad Request`: `ValidationError`
     - `429 Too Many Requests`: `RateLimitedError`
     - `500 Internal Server Error`: `InternalError`

4. **`GET /api/lists/{listId}/tasks`**
   - Description: Query tasks belonging to a list with optional filters.
   - Path Parameter:
     - `listId` (UUID string, required)
   - Query Parameters:
     - `status` ("open" | "done", optional)
     - `priority` ("low" | "medium" | "high", optional)
     - `dueBefore` (date string `YYYY-MM-DD`, optional)
     - `limit` (integer, optional, default: 50, min: 1, max: 200)
     - `offset` (integer, optional, default: 0, min: 0)
   - Responses:
     - `200 OK`: `{ items: Task[], total: number }`
     - `400 Bad Request`: `ValidationError` (invalid query parameter values)
     - `404 Not Found`: `NotFoundError` (list does not exist)
     - `500 Internal Server Error`: `InternalError`

5. **`POST /api/lists/{listId}/tasks`**
   - Description: Create a new task within a specified list.
   - Path Parameter:
     - `listId` (UUID string, required)
   - Request Body: `application/json` -> `CreateTaskInput` (`{ title: string, priority?: "low" | "medium" | "high", dueDate?: string }`)
   - Responses:
     - `201 Created`: `Task` object. Header: `Location: /api/tasks/{id}`
     - `400 Bad Request`: `ValidationError`
     - `404 Not Found`: `NotFoundError` (list does not exist)
     - `429 Too Many Requests`: `RateLimitedError`
     - `500 Internal Server Error`: `InternalError`

6. **`PATCH /api/tasks/{id}`**
   - Description: Partially update task fields (requires at least one field).
   - Path Parameter:
     - `id` (UUID string, required)
   - Request Body: `application/json` -> `PatchTaskInput` (`{ title?: string, priority?: "low" | "medium" | "high", dueDate?: string | null }`)
   - Responses:
     - `200 OK`: `Task` object (updated)
     - `400 Bad Request`: `ValidationError` (empty body or invalid values)
     - `404 Not Found`: `NotFoundError` (task does not exist)
     - `429 Too Many Requests`: `RateLimitedError`
     - `500 Internal Server Error`: `InternalError`

7. **`DELETE /api/tasks/{id}`**
   - Description: Permanently delete a task.
   - Path Parameter:
     - `id` (UUID string, required)
   - Responses:
     - `204 No Content`: Empty body
     - `404 Not Found`: `NotFoundError` (task does not exist)
     - `429 Too Many Requests`: `RateLimitedError`
     - `500 Internal Server Error`: `InternalError`

8. **`POST /api/tasks/{id}/complete`**
   - Description: Mark a task as complete (`status = 'done'`).
   - Path Parameter:
     - `id` (UUID string, required)
   - Responses:
     - `200 OK`: `Task` object (with `completedAt` timestamp)
     - `404 Not Found`: `NotFoundError` (task does not exist)
     - `409 Conflict`: `ConflictError` (`already_done` if task is already done)
     - `429 Too Many Requests`: `RateLimitedError`
     - `500 Internal Server Error`: `InternalError`

9. **`POST /api/tasks/{id}/reopen`**
   - Description: Reopen a completed task (`status = 'open'`).
   - Path Parameter:
     - `id` (UUID string, required)
   - Responses:
     - `200 OK`: `Task` object (with `completedAt = null`)
     - `404 Not Found`: `NotFoundError` (task does not exist)
     - `409 Conflict`: `ConflictError` (`already_open` if task is already open)
     - `429 Too Many Requests`: `RateLimitedError`
     - `500 Internal Server Error`: `InternalError`

### Data

The OpenAPI schema definitions mirror the relational schema defined in `server/src/schema.sql` and the runtime TypeScript models:

#### Database to OpenAPI Data Mapping

| Entity | Field | DB Type | OpenAPI 3.1 Type | Constraints & Description |
|---|---|---|---|---|
| `List` | `id` | `TEXT` | `string` (format: `uuid`) | Primary key, generated with `randomUUID()` |
| `List` | `name` | `TEXT` | `string` | 1–100 characters, trimmed |
| `List` | `createdAt` | `TEXT` | `string` (format: `date-time`) | ISO-8601 timestamp |
| `List` | `updatedAt` | `TEXT` | `string` (format: `date-time`) | ISO-8601 timestamp |
| `Task` | `id` | `TEXT` | `string` (format: `uuid`) | Primary key, generated with `randomUUID()` |
| `Task` | `listId` | `TEXT` | `string` (format: `uuid`) | Foreign key references `lists(id)` ON DELETE CASCADE |
| `Task` | `title` | `TEXT` | `string` | 1–200 characters, trimmed |
| `Task` | `status` | `TEXT` | `string` (enum) | `"open"` \| `"done"`, default `"open"` |
| `Task` | `priority` | `TEXT` | `string` (enum) | `"low"` \| `"medium"` \| `"high"`, default `"medium"` |
| `Task` | `dueDate` | `TEXT` | `string` (format: regex) \| `null` | Pattern: `^\d{4}-\d{2}-\d{2}$` (YYYY-MM-DD) or `null` |
| `Task` | `createdAt` | `TEXT` | `string` (format: `date-time`) | ISO-8601 timestamp |
| `Task` | `updatedAt` | `TEXT` | `string` (format: `date-time`) | ISO-8601 timestamp |
| `Task` | `completedAt` | `TEXT` | `string` (format: `date-time`) \| `null` | ISO-8601 timestamp when completed, `null` when open |

#### Standard Error Response Envelope
All error responses adhere to the standard envelope defined in `server/src/middleware/errors.ts`:
```json
{
  "error": {
    "code": "validation_error | not_found | already_done | already_open | rate_limited | internal_error",
    "message": "Human-readable explanation of the error"
  }
}
```

### Flows

#### Flow 1: Client Ingests OpenAPI Document
```
Client / Runner                Express (app.ts)            docsRouter (docs.ts)        openapi.ts
      |                               |                           |                        |
      |--- GET /api/openapi.json ---->|                           |                        |
      |                               |---- route match --------->|                        |
      |                               |                           |-- read pre-computed -->|
      |                               |                           |   JSON string          |
      |                               |                           |<-- buffer / string ----|
      |                               |                           |-- set headers:         |
      |                               |                           |   Content-Type: json   |
      |                               |                           |   Cache-Control: 3600  |
      |                               |                           |   nosniff, DENY        |
      |<-- 200 OK (OpenAPI Spec) -----|<--------------------------|                        |
```

#### Flow 2: Browser User Explores Swagger UI Interactive Docs
```
Browser                       Express (app.ts)            docsRouter (docs.ts)         swagger-ui-dist
   |                                 |                           |                           |
   |--- GET /api/docs -------------->|                           |                           |
   |                                 |---- route match --------->|                           |
   |                                 |                           |-- set CSP:                |
   |                                 |                           |   style-src 'unsafe-inline'|
   |                                 |                           |   img-src data:           |
   |                                 |                           |   script-src 'self'       |
   |<-- 200 OK (HTML Shell) ---------|<--------------------------|                           |
   |                                 |                           |                           |
   |--- GET /api/docs/swagger-ui.css>|-------------------------->|--- serve static --------->|
   |<-- 200 OK (CSS) ----------------|<--------------------------|<--------------------------|
   |                                 |                           |                           |
   |--- GET .../swagger-ui-bundle.js>|-------------------------->|--- serve static --------->|
   |<-- 200 OK (JS) -----------------|<--------------------------|<--------------------------|
   |                                 |                           |                           |
   |--- GET .../swagger-initializer->|-------------------------->|-- serve initializer script|
   |<-- 200 OK (JS Initializer) -----|<--------------------------|                           |
   |                                 |                           |                           |
   |--- GET /api/openapi.json ------>|-------------------------->|-- serve cached spec ----->|
   |<-- 200 OK (JSON Contract) ------|<--------------------------|                           |
   |                                 |                           |                           |
   |-- Swagger UI renders UI --------|                           |                           |
```

## Alternatives considered

1. **Runtime reflection from Express router layers**:
   - *Approach*: Inspecting `app._router.stack` to construct paths dynamically.
   - *Rejection*: Express route stacks lack metadata about request body schemas, query parameters, and response types. Zod validation handlers are generic middleware functions whose inner schemas cannot be inspected reliably without custom metadata wrappers.
2. **Handwritten static `openapi.yaml`**:
   - *Approach*: Maintaining a YAML file manually in `docs/openapi.yaml`.
   - *Rejection*: Introduces high risk of documentation drift and synchronization errors over time whenever route schemas in `server/src/routes/` are updated or new validation constraints are introduced.
3. **`swagger-ui-express` npm package**:
   - *Approach*: Using `swagger-ui-express` convenience middleware.
   - *Rejection*: Relies on default HTML templates that embed inline scripts violating strict `script-src 'self'` CSP policies, and introduces extraneous transitive dependencies. Serving `swagger-ui-dist` with a dedicated `swagger-initializer.js` gives full, deterministic control over HTML headers, caching, and CSP directives.
4. **Third-party CDN assets for Swagger UI**:
   - *Approach*: Loading Swagger UI bundles from `unpkg.com` or `cdnjs`.
   - *Rejection*: Violates the `security-baseline` requirement of `default-src 'self'`, introduces external availability risks, and prevents offline/local development.

## Security and privacy

- **Content Security Policy (CSP)**:
  - Global CSP configured in `server/src/app.ts` is `default-src 'self'`.
  - Swagger UI requires inline styles for dynamic theming and layout; hence, the route-scoped middleware for `/api/docs` allows `style-src 'self' 'unsafe-inline'` and `img-src 'self' data:`.
  - `script-src` remains strictly `'self'`: the initialization script is served as a separate static file at `/api/docs/swagger-initializer.js` rather than an inline `<script>` block. Serving default `index.html` from `swagger-ui-dist` is disabled via `{ index: false }` and all entrypoints (`/api/docs`, `/api/docs/`, `/api/docs/index.html`) route to the CSP-compliant custom HTML template.
  - `connect-src` remains `'self'`, permitting the Swagger UI client to fetch `/api/openapi.json` from the origin.
- **Header Hardening**:
  - `X-Content-Type-Options: nosniff` is enforced on `/api/openapi.json` and all Swagger UI assets.
  - `X-Frame-Options: DENY` is retained to prevent clickjacking.
- **Information Leakage**:
  - The OpenAPI document only exposes public API paths and standardized error models. Internal operational endpoints (`/metrics`) and stack traces are excluded, adhering to the project's security baseline.
- **Rate Limiting Consistency**:
  - Mutation endpoints documented in the OpenAPI specification indicate HTTP 429 `rate_limited` responses corresponding to the active `rateLimit` middleware.

## Test approach

A dedicated Vitest test suite will be added at `server/tests/openapi.test.ts`:

1. **OpenAPI 3.1 Spec Schema Validation**:
   - Uses `@apidevtools/swagger-parser` to validate the generated `openApiDocument`:
     ```typescript
     import SwaggerParser from "@apidevtools/swagger-parser";
     import { openApiDocument } from "../src/docs/openapi";

     it("validates against OpenAPI 3.1 schema without errors", async () => {
       const cloned = JSON.parse(JSON.stringify(openApiDocument));
       const api = await SwaggerParser.validate(cloned);
       expect(api).toBeDefined();
       expect(api.openapi).toBe("3.1.0");
     });
     ```
2. **Route and HTTP Method Coverage Assertions**:
   - Compares registered OpenAPI paths and methods against all public API endpoints:
     - `GET /healthz`
     - `GET /api/lists`
     - `POST /api/lists`
     - `GET /api/lists/{listId}/tasks`
     - `POST /api/lists/{listId}/tasks`
     - `PATCH /api/tasks/{id}`
     - `DELETE /api/tasks/{id}`
     - `POST /api/tasks/{id}/complete`
     - `POST /api/tasks/{id}/reopen`
   - Confirms that internal routes (`/metrics`) are *not* present in the OpenAPI specification.
3. **HTTP Endpoint Integration Tests (via `supertest`)**:
   - `GET /api/openapi.json`:
     - Asserts status `200`.
     - Asserts header `Content-Type: application/json; charset=utf-8` (or `application/json`).
     - Asserts header `Cache-Control: public, max-age=3600`.
     - Asserts security headers `X-Content-Type-Options: nosniff` and `X-Frame-Options: DENY`.
     - Validates payload contains `info.title === "Tasklist API"`.
   - `GET /api/docs`, `GET /api/docs/`, and `GET /api/docs/index.html`:
     - Asserts status `200`.
     - Asserts header `Content-Type: text/html; charset=utf-8`.
     - Asserts CSP header includes `style-src 'self' 'unsafe-inline'`.
     - Asserts HTML links to `/api/docs/swagger-ui.css`, `/api/docs/swagger-ui-bundle.js`, and `/api/docs/swagger-initializer.js`.
   - `GET /api/docs/swagger-initializer.js`:
     - Asserts status `200`.
     - Asserts header `Content-Type: application/javascript`.
     - Asserts body contains `/api/openapi.json`.

## Rollout and operations

- **Deployment**: The feature is part of the server build. Dependencies are installed in `server/package.json`, and TypeScript compiles them to `dist/`.
- **Zero-Downtime Migration**: No database migrations or schema alterations are required. Existing routes and middleware continue to function unmodified.
- **Performance**: Pre-computing the specification at module load ensures that serving `/api/openapi.json` incurs zero per-request compilation cost and serves directly from memory.

### Rollback Plan

In the event of a deployment failure, runtime exceptions, security regressions, or client-side CSP compatibility issues:
1. **Revert Git Deployment**: Revert the feature pull request commit on `main`.
2. **Express Setup Restoration**: Reverting `server/src/app.ts` removes `app.use(docsRouter)` from the Express pipeline, immediately restoring the application routing table and default root CSP headers (`default-src 'self'`).
3. **Schema Isolation Restoration**: Reverting `server/src/routes/lists.ts` and `server/src/routes/tasks.ts` restores localized Zod schema definitions without affecting runtime database operations.
4. **Dependency Cleanup**: Reverting `server/package.json` removes `@asteasolutions/zod-to-openapi`, `swagger-ui-dist`, `@apidevtools/swagger-parser`, and `@types/swagger-ui-dist`.
5. **Redeployment**: Execute standard build and deployment pipeline (`npm run build && npm start`). Traffic immediately reverts to the pre-documentation baseline without downtime.

## Risks

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Route contract drift if endpoints change without updating `registry.ts` | Medium | Low | Route handlers import validation schemas directly from `registry.ts`, and the automated coverage test in `server/tests/openapi.test.ts` fails in CI if any route handler exists in Express without a matching OpenAPI definition. |
| Browser CSP violation on Swagger UI UI assets | Medium | Low | Route-scoped CSP middleware explicitly white-lists `'unsafe-inline'` for `style-src` while loading initialization logic from an external file (`/api/docs/swagger-initializer.js`) to keep `script-src 'self'`. Requests to `/api/docs/index.html` are handled explicitly, and `{ index: false }` is set on static asset serving. |
| Bundle size increase on server deployment | Low | Low | `swagger-ui-dist` is ~3MB on disk and only loaded statically when requested; it does not increase server execution memory overhead. |

## Open questions

*None. All interfaces, dependencies, schemas, route specifications, and security policies are settled.*

## Story coverage

| Story | Sections |
|---|---|
| TAS-STORY-1: Schema registry for core models and standard error responses | Design > Components, Design > Interfaces, Design > Data |
| TAS-STORY-2: OpenAPI contract definitions for health and list endpoints | Design > Interfaces, Design > Flows |
| TAS-STORY-3: OpenAPI contract definitions for task querying and mutation endpoints | Design > Interfaces, Design > Data |
| TAS-STORY-4: Serve cached OpenAPI 3.1 specification at /api/openapi.json | Design > Components, Design > Interfaces, Design > Flows, Security and privacy, Test approach |
| TAS-STORY-5: Interactive documentation UI at /api/docs compliant with Content Security Policy | Design > Components, Design > Interfaces, Design > Flows, Security and privacy, Test approach |
| TAS-STORY-6: Automated test suite for OpenAPI schema validity and route coverage | Test approach, Risks |

## Sources

- [server/src/app.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/app.ts)
- [server/src/routes/lists.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/lists.ts)
- [server/src/routes/tasks.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/tasks.ts)
- [server/src/routes/health.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/routes/health.ts)
- [server/src/middleware/errors.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/middleware/errors.ts)
- [server/src/middleware/validate.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/middleware/validate.ts)
- [server/src/schema.sql](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/src/schema.sql)
- [server/package.json](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/package.json)
- [server/tests/validation.test.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/tests/validation.test.ts)
- [server/tests/security.test.ts](https://github.com/agentic-sdlc-demo/app-source/blob/main/server/tests/security.test.ts)
