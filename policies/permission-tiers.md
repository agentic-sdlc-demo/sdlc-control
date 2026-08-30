# Autonomy tiers by environment

Human attention concentrates at gates; everything below a gate runs autonomously.

| Tier | Environment | Agent may | Gate |
|------|-------------|-----------|------|
| 1 | Development (worktrees, local runs) | edit, test, build, run, open PRs | none — branch protection catches everything at merge |
| 2 | Staging (`tasklist-staging`, port 8080) | deploy automatically after merge to `main` | required CI status checks |
| 3 | Production (`tasklist-prod`, port 8081) | request a deploy | `deploy-gate.sh` (deterministic block) **and** a release manager writing the single-use approval token |
| — | Governance (`sdlc-control` itself) | propose changes via PR | human review + `evals/run-evals.sh` must pass |

Rules that hold at every tier:

- No agent merges its own PR; merges happen through human review.
- The 3σ maintenance path may only **file an intent PR** — it never merges or deploys.
- Security-scan findings are dismissed only with a recorded reason.
