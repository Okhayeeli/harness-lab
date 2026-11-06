# Thread THR-002 — What is the attack surface of the pre-install Gitea front page?

status: active
opened: 2026-11-05

## Question
On a fresh (uninstalled) `gitea/gitea:1.22.3` instance, the root path `/`
serves ~22KB of HTML — the install wizard. What endpoints does that page
reference (static assets, form POST target, JS-driven fetches), and are any
of them exploitable without authentication on an uninstalled instance?

The install flow is interesting because: (a) it is unauthenticated by design,
(b) it accepts configuration values that shape the eventual instance
(database path, admin credentials, SMTP, secrets), and (c) historically
installer surfaces are under-tested compared to post-install APIs.

## Current assessment
The entire *state-changing* install surface is **one endpoint**: `POST /` with
42 input fields. That is the attack surface pre-install, period — no other
form, no XHR, no second route. The 42 fields include high-value configuration
inputs that normally require admin trust: `db_host`, `db_passwd`,
`repo_root_path`, `lfs_root_path`, `log_root_path`, `run_user`,
`admin_passwd`, SMTP creds. All of them accept attacker input from an
unauthenticated POST.

Static surface: large asset bundles (`/assets/js/index.js` is 1.1 MB). Where
any client-side install-flow logic lives, that's where to look.

`/api/swagger` is linked from the install page but 404s — same byte-identical
body as THR-001/E-002, so the pre-install API gate is thorough even for
paths the install page itself advertises.

## Evidence
- E-001: Install page surface — 1 form (POST /, 42 fields), 4 static paths probed, /api/swagger gated → evidence/E-001.md

## Next action
Move to server-side validation behaviour on individual high-value fields.
The field that is most likely to produce an interesting response is one
whose value directly becomes a filesystem path on the server:
`repo_root_path`, `lfs_root_path`, `log_root_path`, `db_path`.

**Specifically**: send a `POST /` with the default form body but one field
mutated to a path-traversal-shaped value, then observe whether the server
validates it client-side only, server-side with a sanitising rejection, or
accepts it. Each mutation = one evidence file.

Caution: a successful install mutates the container state irreversibly. Use
a throwaway data volume (`just stop && rm -rf .gitea-data/* && just start`)
between any form-submission experiments so each test starts from the same
pre-install state.

## Reopen condition
n/a (thread is active)

## Reopen condition
n/a (thread is active)
