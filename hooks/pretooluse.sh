#!/usr/bin/env bash
# pretooluse.sh — Claude Code PreToolUse hook.
# Reads the hook payload on stdin, appends one JSON line to the ledger.
# Does NOT block the tool call — pure observation (workshop "Observe").
#
# Payload shape (Claude Code): JSON with tool_name, tool_input, session_id, cwd.

set -euo pipefail
payload="$(cat)"

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${root}/telemetry"

ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
tool=$(printf '%s' "$payload" | jq -r '.tool_name // "unknown"')
sid=$(printf  '%s' "$payload" | jq -r '.session_id // "local"')
# keep the input compact — don't dump huge bodies into the ledger
input=$(printf '%s' "$payload" | jq -c '.tool_input // {} | with_entries(select(.key as $k | ["command","file_path","url","description"] | index($k)))')

printf '{"ts":"%s","session":"%s","event":"PreToolUse","tool":"%s","input":%s}\n' \
  "$ts" "$sid" "$tool" "$input" >> "${root}/telemetry/ledger.jsonl"

# allow the tool call to proceed
exit 0
