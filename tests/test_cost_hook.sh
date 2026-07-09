#!/usr/bin/env bash
# tests/test_cost_hook.sh — executable form of the cost-accounting hook spec.
# Hand-computed truth for the good fixture (see also tests/fixtures/cost/):
#
# Dispatch A = agent-aaaa1111, agent_type "architect", model claude-opus-4-8
#   msg A1 (single line):        input 1000, cw5m 2000, cw1h 0, cr 4000, out 500
#     cost = (1000*5 + 500*25 + 2000*6.25 + 0*10 + 4000*0.5)/1e6 = 32000/1e6 = 0.0320
#   msg A2 (3 dedup snapshots, identical in/cache, out grows 100->300->600):
#                                input 2000, cw5m 0,    cw1h 0, cr 8000, out 600 (max)
#     cost = (2000*5 + 600*25 + 0 + 0 + 8000*0.5)/1e6 = 29000/1e6 = 0.0290
#   Dispatch A opus totals: input 3000, output 1100, cw5m 2000, cw1h 0, cr 12000
#     requests 2, cost 0.0610
#
# Dispatch B = agent-bbbb2222, agent_type "researcher", model claude-sonnet-5
#   msg B1 (INTRO priced, ts 2026-08-15, cache_creation split 5m=1000 1h=500):
#                                input 4000, cw5m 1000, cw1h 500, cr 10000, out 800
#     intro rates (in2 out10 cw5m2.5 cw1h4 cr0.2)
#     cost = (4000*2 + 800*10 + 1000*2.5 + 500*4 + 10000*0.2)/1e6 = 22500/1e6 = 0.0225
#   msg B2 (STANDARD priced, ts 2026-09-01):
#                                input 6000, cw5m 0, cw1h 0, cr 0, out 1000
#     std rates (in3 out15)
#     cost = (6000*3 + 1000*15)/1e6 = 33000/1e6 = 0.0330
#   Dispatch B sonnet totals: input 10000, output 1800, cw5m 1000, cw1h 500, cr 10000
#     requests 2, cost 0.0555
#
# GRAND TOTALS
#   claude-opus-4-8:   input 3000, output 1100, cw5m 2000, cw1h 0,   cr 12000, cost 0.0610
#   claude-sonnet-5:   input 10000, output 1800, cw5m 1000, cw1h 500, cr 10000, cost 0.0555
#   grand cost = 0.1165
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
HOOK="$REPO/hooks/agent-team-cost.sh"
FIXROOT="$HERE/fixtures/cost"
SID="11111111-2222-3333-4444-555555555555"
CWD="/fake/project"                          # slug -> -fake-project
SLUG="-fake-project"
SCRATCH="$(mktemp -d)"
export AGENT_TEAM_COST_DIR="$SCRATCH/costfiles"
export AGENT_TEAM_RATES="$REPO/hooks/model-rates.json"
PASS=0; FAIL=0; RC=0

payload() { # $1 cwd, $2 transcript_path, $3 sid, $4 agentId, $5 agentType
  jq -cn --arg cwd "$1" --arg tp "$2" --arg sid "$3" --arg aid "$4" --arg at "$5" \
    '{session_id:$sid, transcript_path:$tp, cwd:$cwd, hook_event_name:"PostToolUse",
      tool_name:"Agent", tool_response:{agentId:$aid, agentType:$at}}'
}
run_hook() { set +e; printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1; RC=$?; set -u; }
costfile_for() { printf '%s/%s--%s.json' "$AGENT_TEAM_COST_DIR" "$2" "$3"; }  # $2 slug, $3 sid
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

GOOD_TP="$FIXROOT/good/$SID.jsonl"
CF="$(costfile_for "$CWD" "$SLUG" "$SID")"

# Case: a valid fire writes a cost file at the slugged path and exits 0.
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
[ "$RC" -eq 0 ] && ok || no "valid fire exits 0"
[ -f "$CF" ] && ok || no "valid fire writes cost file at slugged path"
jq -e '.status=="ok"' "$CF" >/dev/null 2>&1 && ok || no "valid fire status ok"

# Case: missing session_id -> write nothing, exit 0.
NOSID="$SCRATCH/costfiles/-fake-project--.json"
run_hook "$(jq -cn --arg cwd "$CWD" --arg tp "$GOOD_TP" '{transcript_path:$tp, cwd:$cwd, tool_response:{agentId:"x"}}')"
[ "$RC" -eq 0 ] && ok || no "missing session_id exits 0"
[ ! -f "$NOSID" ] && ok || no "missing session_id writes nothing"

# --- Task 4: exact math over the good fixture (fire once, whole dir scanned) ---
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
j() { jq -r "$1" "$CF"; }   # read a path out of the cost file

# Dispatch A (opus)
[ "$(j '.dispatches.aaaa1111.agent_type')" = "architect" ] && ok || no "A agent_type"
[ "$(j '.dispatches.aaaa1111.requests')" = "2" ] && ok || no "A requests=2 (dedup)"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".input_tokens')" = "3000" ] && ok || no "A opus input"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".output_tokens')" = "1100" ] && ok || no "A opus output (dedup max 600+500)"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cache_write_5m_tokens')" = "2000" ] && ok || no "A opus cw5m"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cache_write_1h_tokens')" = "0" ] && ok || no "A opus cw1h"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cache_read_tokens')" = "12000" ] && ok || no "A opus cr"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd')" = "0.061" ] && ok || no "A opus cost 0.061"

# Dispatch B (sonnet) — intro + standard + 5m/1h split
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".input_tokens')" = "10000" ] && ok || no "B sonnet input"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".output_tokens')" = "1800" ] && ok || no "B sonnet output"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cache_write_5m_tokens')" = "1000" ] && ok || no "B sonnet cw5m"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cache_write_1h_tokens')" = "500" ] && ok || no "B sonnet cw1h"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cache_read_tokens')" = "10000" ] && ok || no "B sonnet cr"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cost_usd')" = "0.0555" ] && ok || no "B sonnet cost 0.0555 (intro+std)"

# Grand totals
[ "$(j '.totals.models."claude-opus-4-8".cost_usd')" = "0.061" ] && ok || no "total opus cost"
[ "$(j '.totals.models."claude-sonnet-5".cost_usd')" = "0.0555" ] && ok || no "total sonnet cost"
[ "$(j '.totals.cost_usd')" = "0.1165" ] && ok || no "grand cost 0.1165"

# --- Task 5: idempotent + incremental ---
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
FIRST="$(cat "$CF")"
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
SECOND="$(cat "$CF")"
# updated_at may differ; compare everything except updated_at.
a="$(printf '%s' "$FIRST"  | jq 'del(.updated_at)')"
b="$(printf '%s' "$SECOND" | jq 'del(.updated_at)')"
[ "$a" = "$b" ] && ok || no "re-fire is idempotent (totals unchanged)"

# Growth: copy the good tree into scratch, append a request to dispatch A, re-fire.
GROW="$SCRATCH/grow"
mkdir -p "$GROW/$SID/subagents"
cp "$FIXROOT/good/$SID.jsonl" "$GROW/$SID.jsonl"
cp "$FIXROOT/good/$SID/subagents/"agent-*.jsonl "$GROW/$SID/subagents/"
# Append one more opus request to A: input 1000, out 100, no cache -> cost 0.0075
cat >> "$GROW/$SID/subagents/agent-aaaa1111.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A3","uuid":"a3","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:02:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A3","type":"message","role":"assistant","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
EOF
GROW_CF="$(costfile_for "$CWD" "$SLUG" "$SID")"
run_hook "$(payload "$CWD" "$GROW/$SID.jsonl" "$SID" aaaa1111 architect)"
# A opus cost now 0.061 + 0.0075 = 0.0685; grand 0.1165 + 0.0075 = 0.124
[ "$(jq -r '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd' "$GROW_CF")" = "0.0685" ] && ok || no "growth updates dispatch A cost to 0.0685"
[ "$(jq -r '.dispatches.aaaa1111.requests' "$GROW_CF")" = "3" ] && ok || no "growth updates dispatch A requests to 3"
[ "$(jq -r '.totals.cost_usd' "$GROW_CF")" = "0.124" ] && ok || no "growth updates grand total to 0.124"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
