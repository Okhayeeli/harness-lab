#!/usr/bin/env bash
# healthz.sh — one bounded question about the target: is it healthy?
# Workshop p.32-36: filter so only the answer reaches the agent.
#
# Raw /api/healthz response for Gitea can include per-check structs.
# We extract only {status, checks_failed_count} — the actual answer.

set -euo pipefail
port="${GITEA_PORT:-13172}"
curl -fsS --max-time 2 "http://127.0.0.1:${port}/api/healthz" \
  | jq -c '{status, failed: ([.checks[]? | select(.status != "pass")] | length)}'
