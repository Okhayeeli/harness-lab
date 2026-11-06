#!/usr/bin/env python3
"""
Build a SQLite oracle of Gitea HTTP routes from the pinned source tree.

Workshop p.54-56: an oracle reveals information about something you don't
have direct access to. For Gitea, that is the full route map with each
route's middleware chain. The answer lives in the Go source, but an LLM
asked to enumerate it produces confident hallucinations.

APPROACH (two-pass, to handle trailing middleware on group closers):
1. Walk the source line by line, maintaining a brace-depth stack of
   groups. Each group starts with `m.Group("<path>", func() {` and ends
   with `})` (or `}, mw1, mw2)`). Middleware attached to EITHER the
   opening Group call OR the closing paren is captured.
2. Collect candidate routes as (lineno, verb, path, handler, raw_rest).
   Don't attach the middleware chain at discovery time — wait until the
   enclosing group has closed, then flush all routes inside that group
   with the finalised middleware chain.

COVERAGE LIMITS (documented honestly):
- Only routers/web/web.go and routers/api/v1/api.go are parsed. Mounted
  packages (actions, lfs, feeds) are not followed.
- `if setting.X { ... }` conditionals are ignored — routes inside are
  recorded unconditionally.
- Middleware passed as a stored variable is recorded by its name only.
- Multi-line Group calls with middleware split across several lines are
  handled via a per-group buffer, but very unusual formatting may miss.

Run:   oracles/routes/build.py
Output: oracles/routes/routes.db
"""
from __future__ import annotations
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / ".gitea-src"
DB = Path(__file__).resolve().parent / "routes.db"

TARGETS = [
    SRC / "routers/web/web.go",
    SRC / "routers/api/v1/api.go",
]

# Strip Go comments (// and /* */) before middleware extraction; otherwise
# a commented-out identifier could be mistaken for a middleware token.
COMMENT_RE = re.compile(r"//.*$|/\*.*?\*/", re.MULTILINE | re.DOTALL)

# Any Go identifier that looks like a middleware reference. Deliberately
# generous — the next layer labels tokens as "known auth" vs "other".
IDENT_RE = re.compile(r"\b([a-zA-Z_][a-zA-Z_0-9]*(?:\.[a-zA-Z_][a-zA-Z_0-9]*)*)\b")

# Tokens that look like Go keywords / primitives / common non-middleware args.
IDENT_BLOCKLIST = {
    "func", "nil", "true", "false", "return", "if", "else", "range",
    "web", "forms", "Bind", "bindIgnErr",
}

# Known auth-enforcing middleware. If NONE of these appear in a route's
# chain, mark auth_known=0 (unknown / probably public) in the DB.
KNOWN_AUTH_MW = {
    "reqSignIn", "reqSignOut", "reqToken", "reqSelfOrAdmin", "reqAdmin",
    "reqSiteAdmin", "reqPackageAccess", "reqRepoReader", "reqRepoWriter",
    "reqRepoAdmin", "reqRepoCodeReader", "reqRepoCodeWriter",
    "reqRepoIssueReader", "reqRepoIssueWriter", "reqRepoPullsReader",
    "reqRepoPullsWriter", "reqRepoReleaseReader", "reqRepoReleaseWriter",
    "reqRepoWikiReader", "reqRepoWikiWriter", "reqOrgOwnership",
    "reqOrgMembership", "reqExploreSignIn", "reqUnitAccess",
    "adminReq", "ignSignIn", "ignExploreSignIn",
    "context.RequireRepoAdmin", "context.RequireRepoWriter",
    "context.RequireRepoReader", "context.RequireSignIn",
    "context.RequireSignInOrBasicAuth",
}

VERB_RE = re.compile(
    r'^\s*m\.(?P<verb>Get|Post|Put|Patch|Delete|Head|Any|Methods)\s*\(\s*'
    r'(?:"(?P<methods>[^"]*)"\s*,\s*)?'
    r'"(?P<path>[^"]*)"\s*'
    r'(?:,\s*(?P<rest>.*))?\s*\)\s*$'
)
GROUP_OPEN_RE = re.compile(
    r'^\s*m\.Group\s*\(\s*"(?P<path>[^"]*)"\s*,\s*func\s*\(\s*\)\s*\{\s*(?P<trailing>.*)$'
)


def extract_mw(s: str | None) -> list[str]:
    """Return all identifier-shaped tokens in s, minus Go keywords / helpers.
    This is deliberately generous — the caller tags which are known auth."""
    if not s:
        return []
    s = COMMENT_RE.sub("", s)
    out = []
    for m in IDENT_RE.finditer(s):
        tok = m.group(1)
        if tok in IDENT_BLOCKLIST:
            continue
        # skip string literals' insides — rough check
        if re.match(r"^[A-Z][A-Z_0-9]*$", tok) and len(tok) < 4:
            continue
        out.append(tok)
    return out


def extract_handler(rest: str | None) -> str:
    """The route handler is the first function-reference-looking identifier
    (contains a '.' or is a known handler-ish name). Falls back to the last
    identifier if nothing dotted is found."""
    if not rest:
        return ""
    s = COMMENT_RE.sub("", rest)
    dotted = re.findall(r"\b[a-z_][a-zA-Z_0-9]*\.[A-Z][a-zA-Z_0-9]+\b", s)
    if dotted:
        return dotted[0]
    toks = re.findall(r"\b[a-zA-Z_][a-zA-Z_0-9]+\b", s)
    toks = [t for t in toks if t not in IDENT_BLOCKLIST]
    return toks[-1] if toks else ""


def parse_file(path: Path) -> list[dict]:
    """Parse one Gitea router file into a list of route rows."""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()

    # Stack frame: {path, mw_inline, mw_trailing, opened, pending_routes}
    # pending_routes accumulate while group is open; flushed on close.
    stack: list[dict] = []
    finalised: list[dict] = []

    # top-level frame so routes outside any group still get captured
    top = {"path": "", "mw_inline": [], "mw_trailing": [], "opened": 0, "pending": []}
    stack.append(top)

    for lineno, line in enumerate(lines, 1):
        stripped = line.rstrip()

        # Group open
        mo = GROUP_OPEN_RE.match(stripped)
        if mo:
            new_frame = {
                "path": mo.group("path"),
                "mw_inline": extract_mw(mo.group("trailing")),
                "mw_trailing": [],
                "opened": lineno,
                "pending": [],
            }
            stack.append(new_frame)
            continue

        # Group close — a brace that closes the func(){ ... } followed by
        # the closing paren of m.Group(). May carry trailing middleware.
        if len(stack) > 1 and re.match(r"^\s*\}\s*(,.*)?\)\s*$", stripped):
            frame = stack.pop()
            frame["mw_trailing"] = extract_mw(stripped)
            this_mw = frame["mw_inline"] + frame["mw_trailing"]

            # PROMOTE the inner frame's pending routes up to the parent,
            # stamped with this group's path prefix and this group's mw.
            # The parent's trailing mw hasn't been parsed yet; it will be
            # added when the parent closes. This cascade continues until
            # we hit the top-level frame (which is flushed at EOF).
            parent = stack[-1]
            for r in frame["pending"]:
                parent["pending"].append(
                    {
                        "verb": r["verb"],
                        "path_frag": frame["path"] + r["path_frag"],
                        "handler": r["handler"],
                        # accumulated middleware: inner group's mw + its own
                        "own_mw": this_mw + r["own_mw"],
                        "lineno": r["lineno"],
                    }
                )
            continue

        # Route verb within current frame
        mv = VERB_RE.match(stripped)
        if mv:
            verb = mv.group("verb")
            methods = mv.group("methods") or ""
            path_frag = mv.group("path")
            own_mw = extract_mw(mv.group("rest"))
            handler = extract_handler(mv.group("rest"))

            verbs_to_emit = []
            if verb == "Methods" and methods:
                verbs_to_emit = [v.strip().upper() for v in re.split(r"[,\s]+", methods) if v.strip()]
            elif verb == "Any":
                verbs_to_emit = ["ANY"]
            else:
                verbs_to_emit = [verb.upper()]

            for v in verbs_to_emit:
                stack[-1]["pending"].append(
                    {
                        "verb": v,
                        "path_frag": path_frag,
                        "handler": handler,
                        "own_mw": own_mw,
                        "lineno": lineno,
                    }
                )

    # flush any routes that were defined outside a group (top frame)
    top = stack[0]
    for r in top["pending"]:
        finalised.append(
            {
                "verb": r["verb"],
                "path": r["path_frag"],
                "mw_chain": ",".join(r["own_mw"]),
                "handler": r["handler"],
                "file": str(path.relative_to(SRC)),
                "lineno": r["lineno"],
            }
        )

    return finalised


def build_db(rows: list[dict]) -> None:
    DB.unlink(missing_ok=True)
    conn = sqlite3.connect(DB)
    conn.execute(
        """CREATE TABLE routes(
            id INTEGER PRIMARY KEY,
            verb TEXT NOT NULL,
            path TEXT NOT NULL,
            mw_chain TEXT NOT NULL,      -- all candidate middleware tokens
            auth_known INTEGER NOT NULL, -- 1 if any KNOWN_AUTH_MW appears
            handler TEXT,
            file TEXT NOT NULL,
            lineno INTEGER NOT NULL
        )"""
    )
    conn.execute("CREATE INDEX idx_verb ON routes(verb)")
    conn.execute("CREATE INDEX idx_auth ON routes(auth_known)")

    for r in rows:
        tokens = [t for t in r["mw_chain"].split(",") if t]
        r["auth_known"] = int(any(t in KNOWN_AUTH_MW for t in tokens))

    conn.executemany(
        "INSERT INTO routes(verb,path,mw_chain,auth_known,handler,file,lineno) "
        "VALUES (:verb,:path,:mw_chain,:auth_known,:handler,:file,:lineno)",
        rows,
    )
    conn.commit()
    conn.close()


def main() -> int:
    if not SRC.exists():
        print(f"ERROR: Gitea source not at {SRC}", file=sys.stderr)
        return 2

    all_rows: list[dict] = []
    for t in TARGETS:
        if not t.exists():
            print(f"WARN: {t} not found; skipping", file=sys.stderr)
            continue
        rs = parse_file(t)
        print(f"parsed {len(rs)} routes from {t.relative_to(SRC)}")
        all_rows.extend(rs)

    build_db(all_rows)
    print(f"wrote {DB}  ({len(all_rows)} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
