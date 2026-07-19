#!/usr/bin/env bash
# tests/test_scoreboard.sh — the scoreboard aggregates machine telemetry records
# (one JSONL record per dispatch, written by the closeout Stop hook via
# hooks/cost_report.py --telemetry-dir) into one row per (role, model):
# dispatch count and total cost_usd, sorted by cost descending.
# Hand-computed truth for the inline fixture (3 records + 1 malformed line):
#   builder / claude-sonnet-5  <- recs 1,2: costs 0.50 + 0.25 -> n=2, 0.7500
#   unattributed bucket        <- rec 3: role "unknown"       -> n=1, 0.1000
#   SKIPPED (malformed: 1): the "not json at all {{{" line
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
SB="$REPO/tools/agent-team-scoreboard.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
cat > "$FIX/-tmp-proj--sess-1.jsonl" <<'EOF'
{"agent_id":"a1","role":"builder","resolved_models":["claude-sonnet-5"],"requests":12,"tokens":{"input":100,"output":50,"cw5m":0,"cw1h":0,"cread":0},"cost_usd":0.50,"session_id":"sess-1"}
{"agent_id":"a2","role":"builder","resolved_models":["claude-sonnet-5"],"requests":8,"tokens":{"input":80,"output":40,"cw5m":0,"cw1h":0,"cread":0},"cost_usd":0.25,"session_id":"sess-1"}
not json at all {{{
{"agent_id":"a3","role":"unknown","resolved_models":["claude-haiku-4-5"],"requests":2,"tokens":{"input":10,"output":5,"cw5m":0,"cw1h":0,"cread":0},"cost_usd":0.10,"session_id":"sess-1"}
EOF

set +e
OUT="$(bash "$SB" "$FIX" 2>&1)"; RC=$?
set -u
[ "$RC" -eq 0 ] && ok || no "scoreboard exits 0 over fixture"

# row ROLE MODEL -> "dispatches cost" for that (role, model) line
row() { printf '%s\n' "$OUT" | awk -v r="$1" -v m="$2" '$1==r && $2==m {print $3, $4}'; }

# Composite (role, model) row: both builder dispatches fold into one row whose
# cost is the sum, counted once per dispatch.
[ "$(row builder claude-sonnet-5)" = "2 0.7500" ] && ok || no "builder/claude-sonnet-5 row: 2 dispatches, 0.7500 (got: $(row builder claude-sonnet-5))"

# Role "unknown" lands in the unattributed bucket, never under a real role.
[ "$(row unattributed "—")" = "1 0.1000" ] && ok || no "unattributed bucket: 1 dispatch, 0.1000 (got: $(row unattributed "—"))"
printf '%s\n' "$OUT" | awk '$1=="unknown"' | grep -q . && no "role unknown must not appear as its own row" || ok
printf '%s\n' "$OUT" | awk '$2=="claude-haiku-4-5"' | grep -q . && no "unknown-role record must not surface under its model" || ok

# Malformed line skipped with a counted warning, not an abort.
printf '%s\n' "$OUT" | grep -q "skipped: 1 malformed" && ok || no "skipped-malformed line counts 1"

# Empty dir -> header only, exit 0.
EMPTY="$(mktemp -d)"
set +e
EOUT="$(bash "$SB" "$EMPTY" 2>&1)"; ERC=$?
set -u
rmdir "$EMPTY" 2>/dev/null
[ "$ERC" -eq 0 ] && ok || no "empty dir exits 0"
[ -z "$(printf '%s\n' "$EOUT" | awk 'NR>1 && NF>0 && $1!="(no"')" ] && ok || no "empty dir prints no data rows"

# Missing directory -> exit 0, no error spew.
set +e
bash "$SB" "$FIX/nope" >/dev/null 2>&1; MRC=$?
set -u
[ "$MRC" -eq 0 ] && ok || no "missing directory exits 0"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
