#!/usr/bin/env bash
# sessionstart.sh — Claude Code SessionStart hook.
# Enrich: inject the current research state at the start of every session
# so the agent doesn't start cold.
# Workshop p.50-53: "Enrich: load current research context at session start."

set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

# ledger that this session started
"$root/hooks/record.sh" SessionStart >/dev/null 2>&1 || true

# emit context that Claude Code will prepend to the session
threads_summary=""
if compgen -G "${root}/threads/active/*/index.md" > /dev/null; then
  threads_summary=$(for f in "${root}"/threads/active/*/index.md; do
    id=$(basename "$(dirname "$f")")
    q=$(awk '/^## Question/{getline; getline; print; exit}' "$f")
    na=$(awk '/^## Next action/{getline; getline; print; exit}' "$f")
    printf -- "- %s: %s  next: %s\n" "$id" "$q" "$na"
  done)
else
  threads_summary="(no active threads)"
fi

cat <<EOF
# harness-lab session context

Target: Gitea at http://127.0.0.1:13172 (see AGENTS.md)

Active threads:
${threads_summary}

Run \`just info\` first if you don't know whether the lab is up.
Record evidence per the report-research-progress skill when an observation
changes an assessment or next action.
EOF
