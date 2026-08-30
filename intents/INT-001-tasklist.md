# INT-001: Shared tasklist for small teams

- **Status:** committed
- **Author:** Shaheen Siddique
- **Date:** 2026-08-31
- **Origin:** conversation

## Problem

Small teams inside the org track work in ad-hoc places — chat threads, personal
notes, spreadsheet rows. Tasks get lost between "mentioned" and "done": there is
no shared view of what is open, who owns it, or what is overdue. Existing suite
tools are too heavy for a five-person team's day-to-day checklist.

## Target users

Teams of 2–10 people who need a shared, low-ceremony task board: the team lead
who assigns and reviews, and members who work the list daily. Single users
organizing personal work are served by the same flows.

## Desired outcomes

- Any team member can see the team's open work in one place, current within seconds of a change.
- Capturing a task takes one action (type + enter); no required fields beyond a title.
- Overdue and due-today work is visible at a glance without opening tasks.
- A task's history (created, completed, reopened) is traceable — who and when.

## Constraints

- Deploys on the org's demo host (Docker Compose, `tasklist-staging`/`tasklist-prod`); single-node, SQLite persistence.
- Must comply with org skills: `api-standards`, `security-baseline`, `ui-brand` (sdlc-control@governance-v0).
- Web app; must work in current Chrome/Firefox/Safari, desktop and mobile widths.
- MVP scope must be buildable in one development phase (Phase 3 of the demo).

## Non-goals

- No integrations (calendar, chat, email notifications) in the MVP.
- No multi-team workspaces, roles/permissions models, or admin console.
- No real-time collaborative editing of a single task; last-write-wins is acceptable.
- No mobile native apps.

## Success metrics

- A new task is captured in under 5 seconds from page load.
- List views (up to 500 tasks) render in under 1 second on the demo host.
- p95 API latency under 200 ms at demo load; `/metrics` exposes it for Stage 6 monitoring.
- Zero security-baseline violations in the Stage 5 review of the implementing PRs.
