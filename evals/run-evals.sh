#!/usr/bin/env bash
# Regression-tests the governance configuration itself. Run on every PR that
# touches skills/ or policies/ (see app-source ci.yml + this repo's checks).
#
# v0 checks are structural: each case in evals/cases/ lists assertions that the
# current skills must satisfy. Later versions replace this with golden-task
# evals (generate an endpoint headlessly, assert the output honors the skills).
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
check() { # check <file> <required-pattern> <label>
  if grep -qiE "$2" "$1"; then
    echo "PASS  $3"
  else
    echo "FAIL  $3 — pattern '$2' missing from $1" >&2
    fail=1
  fi
}

# security-baseline must keep its load-bearing rules
check skills/security-baseline/SKILL.md 'parameterized'        'security: SQL must be parameterized'
check skills/security-baseline/SKILL.md 'No secrets'           'security: no secrets in code'
check skills/security-baseline/SKILL.md 'validation'           'security: input validation on boundaries'

# api-standards must keep the error shape and health endpoints
check skills/api-standards/SKILL.md    '"error"'               'api: standard error shape'
check skills/api-standards/SKILL.md    '/healthz'              'api: liveness endpoint'
check skills/api-standards/SKILL.md    '/metrics'              'api: metrics endpoint (Stage 6 depends on it)'

# managed settings must keep credential reads denied
check policies/managed-settings.json   'github\.token'         'policy: token file read denied'
check policies/managed-settings.json   'deploy-gate'           'policy: deploy gate hook wired'

exit $fail
