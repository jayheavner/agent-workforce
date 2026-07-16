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
payload_m() { # payload() plus a tool_input.model override: $6 model
  jq -cn --arg cwd "$1" --arg tp "$2" --arg sid "$3" --arg aid "$4" --arg at "$5" --arg m "$6" \
    '{session_id:$sid, transcript_path:$tp, cwd:$cwd, hook_event_name:"PostToolUse",
      tool_name:"Agent", tool_input:{model:$m}, tool_response:{agentId:$aid, agentType:$at}}'
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

# --- Telemetry (2026-07-13 dispatch-telemetry spec §2): requested_override ---
# A fire without tool_input.model leaves requested_override null on every entry.
[ "$(j '.dispatches.aaaa1111.requested_override')" = "null" ] && ok || no "no override in payload -> requested_override null"
# A fire WITH tool_input.model stamps ONLY the fired dispatch; siblings stay null.
TEL_CWD="/fake/telem"; TEL_SLUG="-fake-telem"
TEL_CF="$(costfile_for "$TEL_CWD" "$TEL_SLUG" "$SID")"
run_hook "$(payload_m "$TEL_CWD" "$GOOD_TP" "$SID" aaaa1111 architect claude-fable-5)"
[ "$RC" -eq 0 ] && ok || no "override fire exits 0"
jt() { jq -r "$1" "$TEL_CF"; }
[ "$(jt '.dispatches.aaaa1111.requested_override')" = "claude-fable-5" ] && ok || no "fired dispatch stamped requested_override"
[ "$(jt '.dispatches.bbbb2222.requested_override')" = "null" ] && ok || no "non-fired sibling requested_override null"
# Cost math is byte-identical to the spec'd truth: additive field, nothing else moves.
[ "$(jt '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd')" = "0.061" ] && ok || no "override fire: A opus cost still 0.061"
[ "$(jt '.dispatches.bbbb2222.models."claude-sonnet-5".cost_usd')" = "0.0555" ] && ok || no "override fire: B sonnet cost still 0.0555"
[ "$(jt '.totals.cost_usd')" = "0.1165" ] && ok || no "override fire: grand cost still 0.1165"
[ "$(jt '.totals.models | keys | sort | join(",")')" = "claude-opus-4-8,claude-sonnet-5" ] && ok || no "override fire: resolved model keys unchanged"
# A later fire for the OTHER dispatch (no override) preserves the earlier stamp.
run_hook "$(payload "$TEL_CWD" "$GOOD_TP" "$SID" bbbb2222 researcher)"
[ "$(jt '.dispatches.aaaa1111.requested_override')" = "claude-fable-5" ] && ok || no "prior stamp preserved across later fires"
[ "$(jt '.dispatches.bbbb2222.requested_override')" = "null" ] && ok || no "later no-override fire stamps null on its own dispatch"

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

# --- Task 6: unavailable marker ---
MAL_TP="$FIXROOT/malformed/$SID.jsonl"
MAL_CWD="/fake/mal"; MAL_SLUG="-fake-mal"
MAL_CF="$(costfile_for "$MAL_CWD" "$MAL_SLUG" "$SID")"
run_hook "$(payload "$MAL_CWD" "$MAL_TP" "$SID" cccc3333 researcher)"
[ "$RC" -eq 0 ] && ok || no "malformed fire exits 0"
[ "$(jq -r '.status' "$MAL_CF")" = "unavailable" ] && ok || no "malformed -> status unavailable"
[ -n "$(jq -r '.unavailable_reason // empty' "$MAL_CF")" ] && ok || no "malformed -> has a reason"

# An unpriceable model is NOT session-fatal: the record's tokens are trustworthy,
# only its rate is missing. status:"partial", the model's tokens are preserved
# under unpriced_models (no cost invented), and NOTHING is estimated.
UNK_TP="$FIXROOT/unknown/$SID.jsonl"
UNK_CWD="/fake/unk"; UNK_SLUG="-fake-unk"
UNK_CF="$(costfile_for "$UNK_CWD" "$UNK_SLUG" "$SID")"
run_hook "$(payload "$UNK_CWD" "$UNK_TP" "$SID" dddd4444 verifier)"
[ "$RC" -eq 0 ] && ok || no "unknown-model fire exits 0"
[ "$(jq -r '.status' "$UNK_CF")" = "partial" ] && ok || no "unknown-model -> status partial (not unavailable)"
[ "$(jq -r '.unpriced_models."claude-nonexistent-9".input_tokens' "$UNK_CF")" = "100" ] && ok || no "unpriced model tokens preserved at session level"
[ "$(jq -r '.unpriced_models."claude-nonexistent-9".output_tokens' "$UNK_CF")" = "10" ] && ok || no "unpriced model output tokens preserved"
[ "$(jq -r '.dispatches.dddd4444.unpriced_models."claude-nonexistent-9".input_tokens' "$UNK_CF")" = "100" ] && ok || no "unpriced tokens preserved on the dispatch entry"
[ "$(jq -r '.dispatches.dddd4444.models | length' "$UNK_CF")" = "0" ] && ok || no "unpriceable dispatch has no priced models"
[ "$(jq -r '.totals.cost_usd' "$UNK_CF")" = "0" ] && ok || no "no cost invented for unpriced model"
[ "$(jq -e '.dispatches.dddd4444.unpriced_models | has("cost_usd") | not' "$UNK_CF" >/dev/null 2>&1; echo $?)" = "0" ] && ok || no "unpriced entry carries NO cost field (no estimate)"

# Fail-open: an unpriceable dispatch beside priceable ones leaves the priceable
# ones EXACTLY priced (they are not blocked), and the session is partial.
FO="$SCRATCH/failopen"
mkdir -p "$FO/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$FO/$SID.jsonl"
# good opus dispatch: input 1000, out 100, no cache -> (1000*5 + 100*25)/1e6 = 0.0075
cat > "$FO/$SID/subagents/agent-good1111.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"good1111","requestId":"req_G1","uuid":"g1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_G1","type":"message","role":"assistant","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
EOF
# unpriceable dispatch
cat > "$FO/$SID/subagents/agent-badd2222.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"badd2222","requestId":"req_B1","uuid":"b1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-madeup-42","id":"msg_B1","type":"message","role":"assistant","usage":{"input_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
EOF
FO_CWD="/fake/fo"; FO_SLUG="-fake-fo"
FO_CF="$(costfile_for "$FO_CWD" "$FO_SLUG" "$SID")"
run_hook "$(payload "$FO_CWD" "$FO/$SID.jsonl" "$SID" good1111 architect)"
[ "$(jq -r '.status' "$FO_CF")" = "partial" ] && ok || no "fail-open: mixed session is partial"
[ "$(jq -r '.dispatches.good1111.models."claude-opus-4-8".cost_usd' "$FO_CF")" = "0.0075" ] && ok || no "fail-open: priceable sibling still exact 0.0075"
[ "$(jq -r '.totals.cost_usd' "$FO_CF")" = "0.0075" ] && ok || no "fail-open: totals count only exactly-priced tokens"
[ "$(jq -r '.unpriced_models."claude-madeup-42".input_tokens' "$FO_CF")" = "500" ] && ok || no "fail-open: unpriced model surfaced with its tokens"

# Self-heal: add the missing rate; a later fire re-prices it EXACTLY -> status ok.
HEAL_RATES="$SCRATCH/heal-rates.json"
jq '.models."claude-madeup-42" = {input:5.00,output:25.00,cache_write_5m:6.25,cache_write_1h:10.00,cache_read:0.50}' \
  "$REPO/hooks/model-rates.json" > "$HEAL_RATES"
export AGENT_TEAM_RATES="$HEAL_RATES"
run_hook "$(payload "$FO_CWD" "$FO/$SID.jsonl" "$SID" good1111 architect)"
export AGENT_TEAM_RATES="$REPO/hooks/model-rates.json"
[ "$(jq -r '.status' "$FO_CF")" = "ok" ] && ok || no "self-heal: partial re-prices to ok once rate added"
[ "$(jq -e 'has("unpriced_models") | not' "$FO_CF" >/dev/null 2>&1; echo $?)" = "0" ] && ok || no "self-heal: unpriced_models cleared after healing"
# madeup-42: (500*5 + 50*25)/1e6 = 3750/1e6 = 0.00375 ; grand = 0.0075 + 0.00375 = 0.01125
[ "$(jq -r '.dispatches.badd2222.models."claude-madeup-42".cost_usd' "$FO_CF")" = "0.00375" ] && ok || no "self-heal: healed model prices to 0.00375"
[ "$(jq -r '.totals.cost_usd' "$FO_CF")" = "0.01125" ] && ok || no "self-heal: grand total now 0.01125"

# Partial is NOT sticky (unlike unavailable): a later fire can improve it (shown above).
# Genuine corruption remains sticky-unavailable (covered by the mid-bad test below).

# Sticky: after malformed, a fire over the GOOD tree at the SAME cost file stays unavailable.
run_hook "$(payload "$MAL_CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
[ "$(jq -r '.status' "$MAL_CF")" = "unavailable" ] && ok || no "unavailable is sticky for the session"

# --- Task 7: empty state ---
EMPTY_CWD="/fake/empty"; EMPTY_SLUG="-fake-empty"
EMPTY_TP="$SCRATCH/empty/$SID.jsonl"   # no subagents dir exists alongside it
mkdir -p "$SCRATCH/empty"
printf '%s\n' '{"type":"user"}' > "$EMPTY_TP"
EMPTY_CF="$(costfile_for "$EMPTY_CWD" "$EMPTY_SLUG" "$SID")"
run_hook "$(payload "$EMPTY_CWD" "$EMPTY_TP" "$SID" eeee5555 scribe)"
[ "$RC" -eq 0 ] && ok || no "empty subagents dir exits 0"
[ "$(jq -r '.status' "$EMPTY_CF")" = "ok" ] && ok || no "empty subagents dir -> status ok"
[ "$(jq -r '.totals.cost_usd' "$EMPTY_CF")" = "0" ] && ok || no "empty subagents dir -> zero cost"

# --- Task 8: server web-tool counts carried, not priced ---
WT="$SCRATCH/webtool"
mkdir -p "$WT/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$WT/$SID.jsonl"
cat > "$WT/$SID/subagents/agent-ffff6666.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"ffff6666","requestId":"req_W1","uuid":"w1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_W1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10,"server_tool_use":{"web_search_requests":3,"web_fetch_requests":2}}}}
EOF
WT_CWD="/fake/wt"; WT_SLUG="-fake-wt"
WT_CF="$(costfile_for "$WT_CWD" "$WT_SLUG" "$SID")"
run_hook "$(payload "$WT_CWD" "$WT/$SID.jsonl" "$SID" ffff6666 researcher)"
[ "$(jq -r '.totals.web_search_requests' "$WT_CF")" = "3" ] && ok || no "web_search_requests carried = 3"
[ "$(jq -r '.totals.web_fetch_requests' "$WT_CF")" = "2" ] && ok || no "web_fetch_requests carried = 2"
# cost is token-only: (100*5 + 10*25)/1e6 = 750/1e6 = 0.00075, unaffected by web counts
[ "$(jq -r '.totals.cost_usd' "$WT_CF")" = "0.00075" ] && ok || no "web-tool request cost is token-only 0.00075"

# --- Dated model IDs resolve to their priced family (rates table = source of truth) ---
# A real usage record carries the dated release id (e.g. claude-haiku-4-5-20251001).
# It must price against, and aggregate under, the un-dated rates key claude-haiku-4-5.
DATED="$SCRATCH/dated"
mkdir -p "$DATED/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$DATED/$SID.jsonl"
cat > "$DATED/$SID/subagents/agent-hhhh7777.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"hhhh7777","requestId":"req_H1","uuid":"h1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-haiku-4-5-20251001","id":"msg_H1","type":"message","role":"assistant","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
EOF
DATED_CWD="/fake/dated"; DATED_SLUG="-fake-dated"
DATED_CF="$(costfile_for "$DATED_CWD" "$DATED_SLUG" "$SID")"
run_hook "$(payload "$DATED_CWD" "$DATED/$SID.jsonl" "$SID" hhhh7777 researcher)"
[ "$RC" -eq 0 ] && ok || no "dated model fire exits 0"
[ "$(jq -r '.status' "$DATED_CF")" = "ok" ] && ok || no "dated model prices ok (not 'model not in rates config')"
# Aggregated under the canonical key, NOT the dated id.
[ "$(jq -r '.dispatches.hhhh7777.models | keys | join(",")' "$DATED_CF")" = "claude-haiku-4-5" ] && ok || no "dated id aggregates under canonical claude-haiku-4-5"
# cost = (1000*1.00 + 100*5.00)/1e6 = 0.0015
[ "$(jq -r '.dispatches.hhhh7777.models."claude-haiku-4-5".cost_usd' "$DATED_CF")" = "0.0015" ] && ok || no "dated haiku prices to 0.0015 under canonical key"

# --- Task 14: transient partial-read is skipped, not sticky (Amendment 2026-07-09) ---
PART_TP="$FIXROOT/partial/$SID.jsonl"
PART_CWD="/fake/part"; PART_SLUG="-fake-part"
PART_CF="$(costfile_for "$PART_CWD" "$PART_SLUG" "$SID")"
run_hook "$(payload "$PART_CWD" "$PART_TP" "$SID" aaaa1111 architect)"
[ "$RC" -eq 0 ] && ok || no "partial fire exits 0"
# The truncated sibling must NOT flip the session to unavailable.
[ "$(jq -r '.status' "$PART_CF")" = "ok" ] && ok || no "partial sibling does NOT go sticky-unavailable"
# The good sibling is still priced.
[ "$(jq -r '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd' "$PART_CF")" = "0.061" ] && ok || no "good sibling still prices to 0.061 despite partial neighbor"
# The partial sibling contributes NO entry this fire (picked up later once complete).
[ "$(jq -r '.dispatches | has("9999pppp")' "$PART_CF")" = "false" ] && ok || no "partial sibling has no entry this fire"

# Once the partial file finishes flushing (becomes valid), a LATER fire folds it in.
GROWP="$SCRATCH/growpart"
mkdir -p "$GROWP/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$GROWP/$SID.jsonl"
cp "$FIXROOT/partial/$SID/subagents/agent-aaaa1111.jsonl" "$GROWP/$SID/subagents/"
# The completed version of 9999pppp: the truncated tail is now a valid, newline-terminated line.
printf '%s\n%s\n' \
  '{"type":"assistant","isSidechain":true,"agentId":"9999pppp","requestId":"req_P1","uuid":"p1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_P1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}' \
  '{"type":"assistant","isSidechain":true,"agentId":"9999pppp","requestId":"req_P2","uuid":"p2","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:01.000Z","message":{"model":"claude-opus-4-8","id":"msg_P2","type":"message","role":"assistant","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}' \
  > "$GROWP/$SID/subagents/agent-9999pppp.jsonl"
GROWP_CF="$(costfile_for "$PART_CWD" "$PART_SLUG" "$SID")"
run_hook "$(payload "$PART_CWD" "$GROWP/$SID.jsonl" "$SID" 9999pppp researcher)"
[ "$(jq -r '.status' "$GROWP_CF")" = "ok" ] && ok || no "later fire stays ok after partial completes"
[ "$(jq -r '.dispatches | has("9999pppp")' "$GROWP_CF")" = "true" ] && ok || no "completed partial IS folded in on later fire (self-heal)"
# 9999pppp cost = P1 (100*5+10*25)/1e6=0.00075 + P2 (50*5+5*25)/1e6=0.000375 = 0.001125
[ "$(jq -r '.dispatches."9999pppp".models."claude-opus-4-8".cost_usd' "$GROWP_CF")" = "0.001125" ] && ok || no "completed partial prices to 0.001125"

# 0-byte sibling alongside a good one: skipped, good one still priced, not sticky.
ZERO="$SCRATCH/zero"
mkdir -p "$ZERO/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$ZERO/$SID.jsonl"
cp "$FIXROOT/partial/$SID/subagents/agent-aaaa1111.jsonl" "$ZERO/$SID/subagents/"
: > "$ZERO/$SID/subagents/agent-0000zzzz.jsonl"   # 0-byte sibling
ZERO_CWD="/fake/zero"; ZERO_SLUG="-fake-zero"
ZERO_CF="$(costfile_for "$ZERO_CWD" "$ZERO_SLUG" "$SID")"
run_hook "$(payload "$ZERO_CWD" "$ZERO/$SID.jsonl" "$SID" aaaa1111 architect)"
[ "$(jq -r '.status' "$ZERO_CF")" = "ok" ] && ok || no "0-byte sibling does NOT go sticky"
[ "$(jq -r '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd' "$ZERO_CF")" = "0.061" ] && ok || no "0-byte sibling: good dispatch still priced"
[ "$(jq -r '.dispatches | has("0000zzzz")' "$ZERO_CF")" = "false" ] && ok || no "0-byte sibling has no entry this fire"

# A bad line in the MIDDLE (good line after it) is genuine corruption -> sticky.
MIDBAD="$SCRATCH/midbad"
mkdir -p "$MIDBAD/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$MIDBAD/$SID.jsonl"
printf '%s\n%s\n%s\n' \
  '{"type":"assistant","isSidechain":true,"agentId":"7777mmmm","message":{"model":"claude-opus-4-8","id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}' \
  'not json at all {{{' \
  '{"type":"assistant","isSidechain":true,"agentId":"7777mmmm","message":{"model":"claude-opus-4-8","id":"m2","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}' \
  > "$MIDBAD/$SID/subagents/agent-7777mmmm.jsonl"
MIDBAD_CWD="/fake/midbad"; MIDBAD_SLUG="-fake-midbad"
MIDBAD_CF="$(costfile_for "$MIDBAD_CWD" "$MIDBAD_SLUG" "$SID")"
run_hook "$(payload "$MIDBAD_CWD" "$MIDBAD/$SID.jsonl" "$SID" 7777mmmm researcher)"
[ "$(jq -r '.status' "$MIDBAD_CF")" = "unavailable" ] && ok || no "bad line in middle stays genuine -> unavailable"

# --- Task 16: non-UUID session_id is rejected (path confinement) ---
BADSID_CWD="/fake/badsid"; BADSID_SLUG="-fake-badsid"
BADSID="../../etc/evil"                       # not a UUID; would escape the dir
BADSID_CF="$AGENT_TEAM_COST_DIR/$BADSID_SLUG--$BADSID.json"
run_hook "$(payload "$BADSID_CWD" "$GOOD_TP" "$BADSID" aaaa1111 architect)"
[ "$RC" -eq 0 ] && ok || no "non-UUID session_id exits 0"
[ ! -f "$BADSID_CF" ] && ok || no "non-UUID session_id writes nothing"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
