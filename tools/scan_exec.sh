#!/usr/bin/env bash
# scan_exec.sh — run the deterministic exec.Command inventory against the
# pinned target checkout, compare to the saved baseline, surface only CHANGED
# expressions (not line moves).
#
# Workshop p.45-49:
#   rule + scan + saved comparison → which changes need review.
# Coverage note: default ignores skip test files; we explicitly include them.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="${GITEA_SRC:-${root}/.gitea-src}"
rule="${root}/scans/exec-command.yml"
out_dir="${root}/scans/results"
mkdir -p "$out_dir"

ts="$(date -u +%Y-%m-%dT%H%M%SZ)"
cur="${out_dir}/exec.${ts}.json"
base="${out_dir}/exec.baseline.json"

if [[ ! -d "$src" ]]; then
  echo "BLOCKED  target source not at ${src}"
  echo "         clone pinned Gitea source there, e.g.:"
  echo "         git clone --depth 1 --branch v1.22.3 https://github.com/go-gitea/gitea ${src}"
  exit 2
fi

if ! command -v semgrep >/dev/null 2>&1; then
  echo "BLOCKED  semgrep not installed"
  exit 2
fi

# --no-git-ignore keeps test/vendored files visible; coverage note p.49
semgrep --config "$rule" --json --no-git-ignore --quiet "$src" > "$cur.raw"

# Freeze the source line text into the JSON at scan time, so later edits to
# source don't retroactively change what the baseline "remembers".
# Semgrep OSS stuffs .extra.lines with "requires login" — we overwrite it.
python3 - "$cur.raw" "$cur" <<'PY'
import json, sys, pathlib
inp, outp = sys.argv[1], sys.argv[2]
data = json.loads(pathlib.Path(inp).read_text())
for r in data.get("results", []):
    try:
        text = pathlib.Path(r["path"]).read_text(encoding="utf-8", errors="replace").splitlines()
        snip = " ".join(text[r["start"]["line"]-1 : r["end"]["line"]]).strip()
        r["extra"]["lines"] = snip
    except Exception as e:
        r["extra"]["lines"] = f"<unreadable: {e}>"
pathlib.Path(outp).write_text(json.dumps(data))
PY
rm -f "$cur.raw"

n=$(jq '.results | length' "$cur")
echo "scan: ${n} matches  → $(basename "$cur")"

if [[ ! -f "$base" ]]; then
  cp "$cur" "$base"
  echo "baseline: saved initial baseline (no diff on first run)"
  exit 0
fi

# compare by (path relative to .gitea-src + frozen source line text)
diff_file="${out_dir}/exec.${ts}.diff.txt"
jq -r --arg prefix "$src/" '.results[] | "\(.path | sub($prefix; ""))\t\(.extra.lines)"' "$base" | sort -u > "${out_dir}/.base.tsv"
jq -r --arg prefix "$src/" '.results[] | "\(.path | sub($prefix; ""))\t\(.extra.lines)"' "$cur"  | sort -u > "${out_dir}/.cur.tsv"

{
  echo "=== removed (in baseline, not in current) ==="
  comm -23 "${out_dir}/.base.tsv" "${out_dir}/.cur.tsv"
  echo
  echo "=== added (in current, not in baseline) ==="
  comm -13 "${out_dir}/.base.tsv" "${out_dir}/.cur.tsv"
} > "$diff_file"

rm -f "${out_dir}/.base.tsv" "${out_dir}/.cur.tsv"

added=$(grep -c . <(sed -n '/=== added/,$p' "$diff_file" | tail -n +2) || true)
removed=$(grep -c . <(sed -n '/=== removed/,/=== added/p' "$diff_file" | tail -n +2 | head -n -2) || true)

echo "diff: +${added} -${removed}  → $(basename "$diff_file")"
echo "(line-only moves do NOT appear here; only changed expressions do.)"
