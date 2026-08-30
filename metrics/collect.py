#!/usr/bin/env python3
"""Renders dashboard.md from the artifact chain and Actions history.

Leading indicators
  - intent -> spec time: merge timestamp of INT-* PR vs SPEC-* PR
  - first-pass CI success rate: share of PRs whose first check run succeeded
  - repos on security-scan schedule

Lagging indicators
  - escaped defects: intents with Origin: incident
  - requirements rework: SPEC-* commits after the linked build PR opened

DORA (from deploy workflow history)
  - deployment frequency, lead time (merge -> deploy), change failure rate

v0 is a stub: wire to the GitHub API via GITHUB_TOKEN once Phases 1-5 have
produced enough history to be worth rendering. Run: python3 metrics/collect.py
"""

if __name__ == "__main__":
    print("metrics/collect.py: no history yet — run after Phase 5 produces deploys.")
