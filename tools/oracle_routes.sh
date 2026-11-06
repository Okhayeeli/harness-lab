#!/usr/bin/env bash
# oracle_routes.sh — query the Gitea route oracle
#
# Workshop p.55: "An oracle doesn't make security decisions on its own.
# It provides data that humans or agents can use to make more informed
# decisions."  This CLI returns rows; YOU decide what matters.
#
# IMPORTANT coverage caveat:
#   auth_known=0 means "my parser did not find a known auth-middleware
#   token in this route's chain". It does NOT mean "this route is
#   unauthenticated". False positives exist — treat the auth_known=0
#   list as a candidate pool to spot-check against source, NOT as a
#   finding.
#
# Usage:
#   oracle_routes.sh                              # quick stats
#   oracle_routes.sh verb POST                    # all POST routes
#   oracle_routes.sh unauth [VERB]                # auth_known=0 routes
#   oracle_routes.sh path '%/admin/%'             # path glob (SQL LIKE)
#   oracle_routes.sh handler ReleasesPost         # by handler fragment
#   oracle_routes.sh sql "SELECT verb,path FROM routes WHERE ..."
#   oracle_routes.sh rebuild                      # rerun the parser

set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
db="$root/oracles/routes/routes.db"
build="$root/oracles/routes/build.py"

if [[ ! -f "$db" && "${1:-}" != "rebuild" ]]; then
  echo "oracle not built yet. running the builder once:"
  python3 "$build"
  echo
fi

cmd="${1:-stats}"
shift || true

case "$cmd" in
  stats)
    sqlite3 -column -header "$db" <<SQL
SELECT 'total'          AS metric, COUNT(*) AS n FROM routes
UNION ALL SELECT 'known-auth',     COUNT(*) FROM routes WHERE auth_known=1
UNION ALL SELECT 'unknown-auth',   COUNT(*) FROM routes WHERE auth_known=0;
SELECT verb, COUNT(*) AS n FROM routes GROUP BY verb ORDER BY n DESC;
SQL
    ;;
  verb)
    v="${1:?verb (GET|POST|PUT|PATCH|DELETE|...) required}"
    sqlite3 -column -header "$db" \
      "SELECT verb, path, (CASE auth_known WHEN 1 THEN 'yes' ELSE '?' END) AS auth,
              handler, file||':'||lineno AS loc
       FROM routes WHERE verb='$v' ORDER BY path;"
    ;;
  unauth)
    v="${1:-}"
    where="auth_known=0"
    [[ -n "$v" ]] && where="$where AND verb='$v'"
    sqlite3 -column -header "$db" \
      "SELECT verb, path, handler, file||':'||lineno AS loc, mw_chain
       FROM routes WHERE $where ORDER BY path;"
    ;;
  path)
    pat="${1:?path LIKE pattern required, e.g. '%/admin/%'}"
    sqlite3 -column -header "$db" \
      "SELECT verb, path, (CASE auth_known WHEN 1 THEN 'yes' ELSE '?' END) AS auth,
              handler, file||':'||lineno AS loc
       FROM routes WHERE path LIKE '$pat' ORDER BY path;"
    ;;
  handler)
    frag="${1:?handler fragment required}"
    sqlite3 -column -header "$db" \
      "SELECT verb, path, handler, file||':'||lineno AS loc
       FROM routes WHERE handler LIKE '%$frag%' ORDER BY path;"
    ;;
  sql)
    q="${1:?raw SQL required}"
    sqlite3 -column -header "$db" "$q"
    ;;
  rebuild)
    python3 "$build"
    ;;
  *)
    echo "unknown subcommand: $cmd"
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //;s/^#//'
    exit 2
    ;;
esac
