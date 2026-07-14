#!/usr/bin/env bash
# tests/test_scoreboard.sh — executable form of the dispatch-telemetry spec §5.
# Hand-computed truth for tests/fixtures/telemetry/ (2 files, 9 records, 1 malformed line):
#
#   builder / claude-sonnet-5 / small   <- alpha recs 1,2,3 + beta rec 1
#     n=4; firsts=4 of which pass=3 -> first-try 75%; judged=4, pass=3 -> pass 75%
#     costs [0.10,0.12,0.20,0.30] -> median (0.12+0.20)/2 = 0.16; drift 0
#   builder / claude-opus-4-8 / small   <- alpha rec 4 (repair-1 pass, the upshift row)
#     n=1; no sequence==first -> first-try "—"; pass 100%; median 0.40; drift 0
#   architect / claude-opus-4-8 / standard <- alpha rec 5 (requested sonnet, ran opus)
#     n=1; first-try 100%; pass 100%; median 0.15; drift 1
#   researcher / claude-sonnet-5 / small <- beta rec 2 (n/a sequence+verdict)
#     n=1; first-try "—"; pass "—"; median 0.05; drift 0
#   QUARANTINE (unattributed: 2): alpha rec 7 (claude-mystery-9, not in rates),
#     alpha rec 6 (resolved_model null — cost file was unavailable)
#   SKIPPED (malformed: 1): the "not json at all {{{" line in the alpha file
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
SB="$REPO/tools/agent-team-scoreboard.sh"
FIX="$HERE/fixtures/telemetry"
export AGENT_TEAM_RATES="$REPO/hooks/model-rates.json"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

set +e
OUT="$(bash "$SB" "$FIX" 2>&1)"; RC=$?
set -u
[ "$RC" -eq 0 ] && ok || no "scoreboard exits 0 over fixtures"

# row ROLE MODEL TIER -> "n ft pass median drift" for that group's line
row() { printf '%s\n' "$OUT" | awk -v r="$1" -v m="$2" -v t="$3" '$1==r && $2==m && $3==t {print $4,$5,$6,$7,$8}'; }

[ "$(row builder claude-sonnet-5 small)" = "4 75% 75% 0.16 0" ] && ok || no "builder/sonnet/small row (got: $(row builder claude-sonnet-5 small))"
[ "$(row builder claude-opus-4-8 small)" = "1 — 100% 0.40 0" ] && ok || no "builder/opus/small row — repair-only group has no first-try rate (got: $(row builder claude-opus-4-8 small))"
[ "$(row architect claude-opus-4-8 standard)" = "1 100% 100% 0.15 1" ] && ok || no "architect/opus/standard row carries the drift count (got: $(row architect claude-opus-4-8 standard))"
[ "$(row researcher claude-sonnet-5 small)" = "1 — — 0.05 0" ] && ok || no "researcher n/a row: no first-try, no pass rate (got: $(row researcher claude-sonnet-5 small))"

# Quarantine: unattributed records are counted, never folded into a model row.
printf '%s\n' "$OUT" | grep -q "unattributed: 2" && ok || no "unattributed line counts 2"
printf '%s\n' "$OUT" | grep -q "claude-mystery-9" && no "quarantined model must not appear as a scoreboard row" || ok

# Malformed line skipped with a counted warning, not an abort.
printf '%s\n' "$OUT" | grep -q "skipped: 1 malformed" && ok || no "skipped-malformed line counts 1"

# Drift-true record is bucketed by RESOLVED model: the architect row is opus,
# and no architect/sonnet row exists (never credited to the requested model).
[ -z "$(row architect claude-sonnet-5 standard)" ] && ok || no "drift record not credited to requested model"

# Empty tree -> header only, exit 0.
EMPTY="$(mktemp -d)"
set +e
EOUT="$(bash "$SB" "$EMPTY" 2>&1)"; ERC=$?
set -u
[ "$ERC" -eq 0 ] && ok || no "empty tree exits 0"
[ -z "$(printf '%s\n' "$EOUT" | awk 'NR>1 && NF>0 && $1!="(no"')" ] && ok || no "empty tree prints no data rows"

# Missing directory -> exit 0, no error spew.
set +e
bash "$SB" "$EMPTY/nope" >/dev/null 2>&1; MRC=$?
set -u
[ "$MRC" -eq 0 ] && ok || no "missing directory exits 0"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
