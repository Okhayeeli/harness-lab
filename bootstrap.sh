#!/usr/bin/env bash
# bootstrap.sh — check for every tool the harness assumes and report which
# are missing. Does NOT install anything. Prints the install hint for each.

set -u
status=0

check() {
    local name="$1" install_hint="$2"
    if command -v "$name" >/dev/null 2>&1; then
        printf '  [OK]   %-12s %s\n' "$name" "$(command -v "$name")"
    else
        printf '  [MISS] %-12s install: %s\n' "$name" "$install_hint"
        status=1
    fi
}

echo "Checking harness-lab prerequisites…"
echo
echo "Container runtime (either is fine):"
check podman "sudo apt install podman"
check docker "https://docs.docker.com/engine/install/"
echo
echo "Core utilities:"
check just     "https://github.com/casey/just#installation  (or: cargo install just)"
check curl     "sudo apt install curl"
check jq       "sudo apt install jq"
check git      "sudo apt install git"
check python3  "sudo apt install python3"
check sqlite3  "sudo apt install sqlite3"
echo
echo "Deterministic scanner:"
check semgrep  "pipx install semgrep  (ensure \$HOME/.local/bin is on PATH)"
echo

if [[ "$status" == "0" ]]; then
    echo "OK — all tools present. Next: just setup-src && just start"
else
    echo "Some tools are missing. Install them and rerun ./bootstrap.sh"
fi
exit "$status"
