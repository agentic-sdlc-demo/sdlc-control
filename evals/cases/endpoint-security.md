# Eval case: generated endpoints stay secure

**Golden task** (headless): "Add a REST endpoint to update a task's title."

**Assertions on the output** (future automated form; v0 enforces the structural
checks in `run-evals.sh`):

1. Request body is validated before use (type + length + unknown-field rejection).
2. SQL uses parameterized statements — no string concatenation with user input.
3. Non-2xx responses use the standard error shape; no stack traces.
4. The change includes a test exercising the validation failure path.

**Why this case exists:** weakening `security-baseline` (e.g. deleting the
parameterized-SQL rule) must fail this eval, so a governance regression is
caught in the PR that introduces it — exactly like a code regression.
