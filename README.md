# sdlc-control

Governance layer and system of record for the AI-native SDLC demo. This repo holds the
committed artifacts and enforcement configuration that govern development in
[`app-source`](https://github.com/agentic-sdlc-demo/app-source).

## The artifact chain

`intent.md → spec.md → plan.md → code + tests → PR review → incident record`

Every stage of the lifecycle produces a version-controlled artifact here that the next
stage reads. Git history is the audit trail: who requested what, who approved it.

## Layout

| Path | Purpose |
|------|---------|
| `intents/` | Stage 1 — machine-readable intent documents (`INT-*.md`) |
| `specs/` | Stage 2 — specs generated with skills as constraints (`SPEC-*.md`) |
| `skills/` | Org policies as versioned skills, synced into `app-source/.claude/skills/` |
| `policies/` | `managed-settings.json` (agent permission baseline) and the autonomy tier matrix |
| `hooks/` | Deterministic guardrails (e.g. `deploy-gate.sh` blocks ungated prod deploys) |
| `evals/` | Golden tasks that regression-test the governance config itself |
| `monitoring/` | Western Electric detection (`detect.py`) and runbooks — Stage 6 |
| `workflows/` | Reusable GitHub Actions (Claude PR review, scheduled security scan) |
| `metrics/` | Leading/lagging indicator and DORA collection |

## How app-source consumes this repo

`app-source/scripts/sync-governance.sh` copies `skills/` and `policies/managed-settings.json`
into the app repo at the ref pinned in `app-source/GOVERNANCE_REF`. CI fails on drift.
Changes to governance land here via PR — and any PR touching `skills/` must pass
`evals/run-evals.sh` before merge.
