# Thread THR-001 — Enumerate Gitea API endpoints reachable without auth

status: closed
opened: 2026-11-05
closed: 2026-11-05

## Question
Which Gitea API endpoints return a 200 for an unauthenticated request against
the pinned image, and does any of them reveal information that the UI gates
behind a login?

## Current assessment
**Under this revision (gitea/gitea:1.22.3) with the install wizard not
completed, the `/api/v1/*` surface uniformly returns a byte-identical 46-byte
HTML 404.** All five tested paths — `/api/v1/version`,
`/api/v1/users/search`, `/api/v1/repos/search`, `/api/v1/signing-key.gpg`,
`/api/v1/nodeinfo` — produce the exact same response (md5
`7ad319a53a092f8326102e7e75f46c07`). `/api/healthz` is the only API-adjacent
endpoint that answers; `/` serves the install page. No API v1 endpoint
reveals information pre-install under this configuration.

## Evidence
- E-001: `/api/v1/version` → HTTP 404 HTML on uninstalled instance → evidence/E-001.md
- E-002: 7-path probe shows uniform 404 across `/api/v1/*`, `/api/healthz` + `/` live → evidence/E-002.md

## Reopen condition
Reopen if any of the following change:
- A different Gitea version (not 1.22.3) is in scope.
- The install wizard is completed (behavior post-install is thr-003 territory, not this thread).
- A path outside the five tested here is suspected of answering pre-install.
- A request type other than GET without auth is in scope.

## Reopen condition
n/a (thread is active)
