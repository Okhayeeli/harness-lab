set shell := ["bash", "-uc"]

runtime := env("CONTAINER_RUNTIME", "podman")
image   := "docker.io/gitea/gitea:1.22.3"
name    := "harness-lab-gitea"
port    := "13172"
data    := justfile_directory() + "/.gitea-data"

# show the recorded instance, source, image, and runtime; whether it's running
info:
    @echo "runtime: {{runtime}}"
    @echo "image:   {{image}}"
    @echo "name:    {{name}}"
    @echo "url:     http://127.0.0.1:{{port}}"
    @{{runtime}} ps -a --filter name={{name}} --format 'state: {{{{.State}}}}  id: {{{{.ID}}}}' 2>/dev/null || echo "state: none"

# start an owned Gitea container on loopback only
start:
    @mkdir -p {{data}}
    @{{runtime}} rm -f {{name}} 2>/dev/null || true
    {{runtime}} run -d --name {{name}} \
        -p 127.0.0.1:{{port}}:3000 \
        -v {{data}}:/data \
        {{image}}
    @echo "waiting for readiness…"
    @just ready

# stop only the recorded owned container
stop:
    -{{runtime}} stop {{name}}
    -{{runtime}} rm {{name}}

# follow the recorded owned container's logs
logs:
    {{runtime}} logs -f {{name}}

# readiness check — proves a normal operation succeeds, not just that a container exists
ready:
    @for i in $(seq 1 30); do \
        body=$(curl -fsS --max-time 2 http://127.0.0.1:{{port}}/api/healthz 2>/dev/null || true); \
        if echo "$body" | grep -q '"status"'; then \
            echo "READY  $body"; exit 0; \
        fi; \
        sleep 1; \
    done; \
    echo "BLOCKED  readiness check failed after 30s"; \
    podman logs --tail 40 {{name}} || true; \
    exit 1

# fetch the target's GitHub record (external integration)
gh-record:
    @tools/gh_record.sh go-gitea gitea

# append a custom event to the ledger (manual; hooks do this automatically for tool calls)
ledger event detail="":
    @hooks/record.sh "{{event}}" "{{detail}}"

# tail the telemetry ledger
audit-tail n="20":
    @tail -n {{n}} telemetry/ledger.jsonl 2>/dev/null || echo "ledger empty"

# run the deterministic scan and compare against the saved baseline
scan-exec:
    @tools/scan_exec.sh

# shallow-clone the pinned Gitea source needed by scan-exec and the route oracle
setup-src tag="v1.22.3":
    @if [ -d .gitea-src ]; then \
        echo ".gitea-src already exists; delete it first if you want to re-clone"; \
        exit 0; \
    fi
    git clone --depth 1 --branch {{tag}} --single-branch https://github.com/go-gitea/gitea.git .gitea-src
    @echo
    @echo "cloned Gitea {{tag}}. Next: python3 oracles/routes/build.py"

# list named recipes with their comments
default:
    @just --list
