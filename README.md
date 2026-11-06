# harness-lab

A vulnerability-research workbench for Gitea, built per the method in the
*[un]prompted II · Harness Engineering for Vulnerability Research* workshop
(Helton & Basden, SF Oct 2026).

**AGENTS.md is the real documentation** — read it first. This README is only
for someone cloning the repo onto a new machine for the first time.

## Setup on a new machine

Required tools:

- Container runtime: `podman` (preferred) **or** `docker` (fallback via
  `CONTAINER_RUNTIME=docker`)
- `just`, `curl`, `jq`, `git`, `python3`, `sqlite3` — standard system packages
- `semgrep` — install user-level: `pipx install semgrep`
  (then ensure `~/.local/bin` is on PATH)

Run the bootstrap check:

```bash
./bootstrap.sh
```

It tells you which tools are missing. Nothing is auto-installed — you install
what it names, re-run until it prints `OK`.

## First-run order

```bash
just setup-src     # shallow-clone Gitea v1.22.3 into .gitea-src/
just start         # pull image, run container on 127.0.0.1:13172
just gh-record     # fetch + save go-gitea/gitea GitHub metadata
tools/oracle_routes.sh rebuild   # parse .gitea-src into routes.db
just scan-exec     # semgrep baseline for exec.Command inventory
```

After `just start` prints `READY  {"status":"pass",...}`, open Claude Code in
this directory. The SessionStart hook injects current thread state.

## What's in the repo vs. what isn't

Tracked (travels between machines):

- `AGENTS.md` — the boundary, stop conditions, evidence rule
- `justfile` — named recipes
- `hooks/`, `tools/`, `skills/`, `scans/exec-command.yml`, `oracles/routes/build.py`
- `threads/` — actual research (closed verdicts + open next actions)
- `.claude/settings.json` — hook wiring for Claude Code

Not tracked (per-machine, regenerable):

- `.gitea-src/` — 66MB source checkout, re-cloned by `just setup-src`
- `.gitea-data/` — container's persistent volume; contains secrets if you
  complete the install
- `telemetry/*.jsonl` — session-local event log; fresh on each machine
- `scans/results/` — baselines + diffs; machine-local
- `oracles/routes/routes.db` — SQLite, rebuilt in <1s

## What this is NOT

- Not a scanner — it's a scaffolding for *doing* research credibly
- Not a reusable "framework" — it's Gitea-shaped. Different target → fork and
  rewrite the target-specific bits (justfile image/port, oracle scope, etc.)
- Not a replacement for knowing what you're doing
