#!/usr/bin/env bash
# record.sh EVENT [DETAIL_JSON_FRAGMENT]
# Append one event line to telemetry/ledger.jsonl.
# Called by hooks AND by `just ledger`.
#
# Workshop p.37-40: recorded outside the agent, append-only, one line per event.

set -euo pipefail

event="${1:?event name required}"
detail="${2:-}"

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${root}/telemetry"
ledger="${root}/telemetry/ledger.jsonl"

ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
sid="${HARNESS_SESSION_ID:-local}"

if [[ -n "$detail" ]]; then
  # detail is expected to be a JSON fragment like  "tool":"Bash","command":"ls"
  line="{\"ts\":\"${ts}\",\"session\":\"${sid}\",\"event\":\"${event}\",${detail}}"
else
  line="{\"ts\":\"${ts}\",\"session\":\"${sid}\",\"event\":\"${event}\"}"
fi

printf '%s\n' "$line" >> "$ledger"
