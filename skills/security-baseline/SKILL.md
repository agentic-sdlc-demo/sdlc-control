---
name: security-baseline
description: Org security policy — apply when generating any code, spec, or configuration.
---

# Security baseline

These constraints are applied at generation time, not discovered in review.

1. **No secrets in code or config**: credentials come from the environment only. Never write a token, key, or password into a tracked file. `.env*` and token files stay gitignored.
2. **Input validation on every boundary**: every request body, param, and query string is validated (type, length, allowlist) before use. Use parameterized statements for all SQL — string-built queries are forbidden.
3. **Least-privilege by default**: new endpoints deny by default; document why any endpoint is unauthenticated. Rate-limit mutating endpoints.
4. **Dependency hygiene**: pin direct dependency versions; no new dependency without a one-line justification in the PR description.
5. **Error discipline**: user-facing errors carry no stack traces, file paths, or SQL fragments.
6. **Headers**: serve `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and a restrictive CSP on HTML responses.
7. **Audit trail**: mutations log actor, action, entity id, and timestamp (structured, no payload bodies).
