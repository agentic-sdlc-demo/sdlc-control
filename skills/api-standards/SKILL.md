---
name: api-standards
description: Org REST API conventions — apply when designing or implementing any HTTP endpoint.
---

# API standards

Apply these rules to every endpoint you design or implement.

1. **Resource naming**: plural nouns, kebab-case paths (`/api/task-lists/:id/tasks`). No verbs in paths.
2. **Error shape**: every non-2xx response returns `{ "error": { "code": "<machine_code>", "message": "<human message>" } }`. Never leak stack traces or internal paths.
3. **Validation first**: validate request bodies and params before any business logic; reject unknown fields; return 400 with the field name in `message`.
4. **Pagination**: list endpoints accept `limit` (default 50, max 200) and `offset`; responses include `total`.
5. **Status codes**: 201 + `Location` on create, 204 on delete, 409 for state conflicts, 422 for semantic validation failures.
6. **Timestamps**: ISO-8601 UTC, fields named `createdAt` / `updatedAt`.
7. **Health**: expose `GET /healthz` (liveness, no auth) and `GET /metrics` (latency percentiles + error counters).
