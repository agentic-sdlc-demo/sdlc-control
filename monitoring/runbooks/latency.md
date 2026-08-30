# Runbook: latency breach on tasklist-prod

Used by the headless diagnosis session at 2σ and by humans at any time.

1. Confirm the signal: `python3 monitoring/detect.py <metrics log>` — is the breach sustained or a single spike?
2. Check container health: `docker compose -p tasklist-prod ps` and `logs --since 30m tasklist-prod`.
3. Correlate with change: `git log --oneline --since <breach window>` in app-source — did a deploy land in the window?
4. Check the database: SQLite file size and slow-query log entries in the app logs.
5. Outcome:
   - Cause found and code-shaped → the 3σ path (or a human) files an intent in `intents/` describing the fix; it re-enters the pipeline at Stage 1.
   - Deploy-correlated regression → release manager rolls back: `deploy.sh prod <previous-tag>`.
   - Environmental (host load, disk) → record in the diagnosis report; no intent.
