#!/usr/bin/env bash
# tests/test_cost_report.sh — verifies hooks/cost_report.py, the whole-session
# pricing tool: exact markdown/json reports from transcripts at list rates,
# unpriced models reported as tokens (never estimated), and per-dispatch
# telemetry with role attribution from the session cost file.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TOOL="$ROOT/hooks/cost_report.py"
FIXTURE="$HERE/fixtures/cost/good/11111111-2222-3333-4444-555555555555.jsonl"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cost-report-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Hermetic default: hook-health scans a profile dir; without this, every bare
# invocation below would scan the repo checkout and the suite would depend on
# this machine's file modes. Sections that test hook health override inline.
mkdir -p "$TMP/default-profile"
export AGENT_TEAM_PROFILE="$TMP/default-profile"
PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

expect_contains() { # $1 haystack, $2 fixed string, $3 label
  if printf '%s' "$1" | grep -qF -- "$2"; then
    pass "$3"
  else
    fail "$3 — missing: $2"
  fi
}

expect_not_contains() { # $1 haystack, $2 fixed string, $3 label
  if printf '%s' "$1" | grep -qF -- "$2"; then
    fail "$3 — forbidden: $2"
  else
    pass "$3"
  fi
}

# --- (a) markdown report against the good fixture ---
MD="$(python3 "$TOOL" --transcript "$FIXTURE" 2>/dev/null)"
if [ $? -eq 0 ] && [ -n "$MD" ]; then
  pass "markdown run exits 0 with output"
else
  fail "markdown run exits 0 with output"
fi
expect_contains "$MD" "## Cost report" "markdown carries the cost-report marker"
expect_contains "$MD" "| claude-opus-4-8 |" "markdown has a claude-opus-4-8 row"
expect_contains "$MD" "| claude-sonnet-5 |" "markdown has a claude-sonnet-5 row"
expect_contains "$MD" "| **Total** |" "markdown has a Total row"
expect_contains "$MD" "orchestrator (main session)" "markdown attributes the main session"

# --- (b) json format: parses, numeric total > 0 ---
JSON_OUT="$(python3 "$TOOL" --transcript "$FIXTURE" --format json 2>/dev/null)"
if printf '%s' "$JSON_OUT" | jq -e '(.total_cost_usd | type) == "number" and .total_cost_usd > 0' >/dev/null 2>&1; then
  pass "json format has numeric total_cost_usd > 0"
else
  fail "json format has numeric total_cost_usd > 0 — got: $JSON_OUT"
fi

# --- (c) a model with no rate is reported as exact tokens, never priced ---
UNKNOWN="$TMP/unknown-model.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-07-18T00:00:00.000Z","message":{"id":"msg_u1","model":"claude-made-up-9","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":25,"cache_read_input_tokens":10}}}' > "$UNKNOWN"
UNPRICED_MD="$(python3 "$TOOL" --transcript "$UNKNOWN" 2>/dev/null)"
expect_contains "$UNPRICED_MD" "Unpriced" "unknown model lands in the Unpriced section"
expect_contains "$UNPRICED_MD" "claude-made-up-9: in 100, out 50, cache-write 25, cache-read 10" \
  "unpriced model reports exact token counts"
expect_not_contains "$UNPRICED_MD" "| claude-made-up-9 |" \
  "unknown model gets no priced table row"
expect_contains "$UNPRICED_MD" '**$0.00**' "nothing priceable totals zero, not an estimate"
UNKNOWN_JSON="$(python3 "$TOOL" --transcript "$UNKNOWN" --format json 2>/dev/null)"
if printf '%s' "$UNKNOWN_JSON" | jq -e '.total_cost_usd == 0 and (.unpriced_models | has("claude-made-up-9"))' >/dev/null 2>&1; then
  pass "json reports the unknown model as unpriced with zero total"
else
  fail "json reports the unknown model as unpriced with zero total — got: $UNKNOWN_JSON"
fi

# --- (d) telemetry: one JSONL line per subagent, role from the cost file ---
COST_FILE="$TMP/cost.json"
printf '%s\n' '{"dispatches":{"aaaa1111":{"agent_type":"builder"}}}' > "$COST_FILE"
TELE_DIR="$TMP/telemetry"
python3 "$TOOL" --transcript "$FIXTURE" --cost-file "$COST_FILE" \
  --telemetry-dir "$TELE_DIR" --session-id "sess-tele" --cwd "/work/repo" >/dev/null 2>&1
TELE_FILE="$TELE_DIR/-work-repo--sess-tele.jsonl"
if [ -f "$TELE_FILE" ]; then
  pass "telemetry file written"
else
  fail "telemetry file written — missing $TELE_FILE"
fi
LINES="$(wc -l < "$TELE_FILE" 2>/dev/null | tr -d ' ')"
if [ "$LINES" = "2" ]; then
  pass "one telemetry line per subagent (2 subagents in fixture)"
else
  fail "one telemetry line per subagent (2 subagents in fixture) — got $LINES lines"
fi
if jq -es 'all(has("role") and has("cost_usd") and (.cost_usd | type == "number"))' "$TELE_FILE" >/dev/null 2>&1; then
  pass "every telemetry record has role and numeric cost_usd"
else
  fail "every telemetry record has role and numeric cost_usd"
fi
if jq -es 'any(.agent_id == "aaaa1111" and .role == "builder" and .cost_usd > 0)' "$TELE_FILE" >/dev/null 2>&1; then
  pass "cost-file agent type attributes aaaa1111 as builder with cost"
else
  fail "cost-file agent type attributes aaaa1111 as builder with cost"
fi
if jq -es 'any(.agent_id == "bbbb2222" and .role == "unknown")' "$TELE_FILE" >/dev/null 2>&1; then
  pass "unmapped subagent reports role unknown, never invented"
else
  fail "unmapped subagent reports role unknown, never invented"
fi

# --- (f) undercount warning: dispatches recorded but no subagent transcripts ---
ORPHAN="$TMP/orphan-session.jsonl"
{
  jq -nc '{type:"assistant",message:{id:"msg_o1",model:"claude-sonnet-5",
    content:[{type:"tool_use",id:"tu_o1",name:"Agent",input:{subagent_type:"builder"}}],
    usage:{input_tokens:10,output_tokens:5,cache_creation_input_tokens:0,cache_read_input_tokens:0}},
    timestamp:"2026-07-19T00:00:00.000Z"}'
} > "$ORPHAN"
ORPHAN_MD="$(python3 "$TOOL" --transcript "$ORPHAN" 2>/dev/null)"
expect_contains "$ORPHAN_MD" "WARNING" \
  "dispatches with zero subagent transcripts warn about undercount"
expect_contains "$ORPHAN_MD" "1 Agent dispatch" \
  "undercount warning names the dispatch count"
expect_not_contains "$MD" "WARNING" \
  "good fixture (no dispatches) carries no undercount warning"

# --- (g2) workforce build stamp: every installed run names its version ---
BUILD_MANIFEST="$TMP/agent-team-manifest.json"
jq -n '{commit:"abc1234", installed_at:"2026-07-20T00:00:00Z", files:{}}' > "$BUILD_MANIFEST"
STAMPED_MD="$(AGENT_TEAM_MANIFEST="$BUILD_MANIFEST" python3 "$TOOL" --transcript "$FIXTURE" 2>/dev/null)"
expect_contains "$STAMPED_MD" "Workforce build abc1234 (installed 2026-07-20T00:00:00Z)" \
  "manifest present: report names the installed build"
STAMPED_JSON="$(AGENT_TEAM_MANIFEST="$BUILD_MANIFEST" python3 "$TOOL" --transcript "$FIXTURE" --format json 2>/dev/null)"
if printf '%s' "$STAMPED_JSON" | jq -e '.workforce_build.commit == "abc1234"' >/dev/null 2>&1; then
  pass "json format carries workforce_build.commit"
else
  fail "json format carries workforce_build.commit — got: $STAMPED_JSON"
fi
expect_not_contains "$MD" "Workforce build" \
  "no manifest beside the tool: no build line invented"

# --- (h) hook health: broken hook infrastructure surfaces in every report ---
HPROF="$TMP/hook-profile"
mkdir -p "$HPROF/hooks"
printf '#!/bin/sh\nexit 0\n' > "$HPROF/hooks/dead-gate.sh"    # exec bit deliberately absent
printf '#!/bin/sh\nexit 0\n' > "$HPROF/hooks/orphan.sh"       # not wired in settings either
jq -n --arg cmd "$HPROF/hooks/dead-gate.sh" \
  '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$cmd}]}],
           SessionStart:[{hooks:[{type:"command",command:"/nonexistent/session-status.sh"}]}]}}' \
  > "$HPROF/settings.json"
HH_MD="$(AGENT_TEAM_PROFILE="$HPROF" python3 "$TOOL" --transcript "$FIXTURE" 2>/dev/null)"
expect_contains "$HH_MD" "chmod +x $HPROF/hooks/dead-gate.sh" \
  "non-executable wired hook: report carries the exact chmod fix"
expect_contains "$HH_MD" "chmod +x $HPROF/hooks/orphan.sh" \
  "non-executable script in hooks dir caught even when unwired"
expect_contains "$HH_MD" "/nonexistent/session-status.sh" \
  "missing hook target is reported"
if [ "$(printf '%s\n' "$HH_MD" | grep -c "dead-gate.sh")" -eq 1 ]; then
  pass "hook wired in settings AND present in hooks dir warns once, not twice"
else
  fail "hook wired in settings AND present in hooks dir warns once, not twice"
fi
HH_JSON="$(AGENT_TEAM_PROFILE="$HPROF" python3 "$TOOL" --transcript "$FIXTURE" --format json 2>/dev/null)"
if printf '%s' "$HH_JSON" | jq -e '.hook_health | length == 3' >/dev/null 2>&1; then
  pass "json format carries all three hook_health warnings"
else
  fail "json format carries all three hook_health warnings — got: $HH_JSON"
fi
HEALTHY="$TMP/healthy-profile"
mkdir -p "$HEALTHY"
CLEAN_MD="$(AGENT_TEAM_PROFILE="$HEALTHY" python3 "$TOOL" --transcript "$FIXTURE" 2>/dev/null)"
expect_not_contains "$CLEAN_MD" "WARNING: hook" \
  "healthy profile: report stays quiet about hooks"
HH_ONLY="$(AGENT_TEAM_PROFILE="$HPROF" python3 "$TOOL" --hook-health 2>/dev/null)"
expect_contains "$HH_ONLY" "chmod +x $HPROF/hooks/dead-gate.sh" \
  "--hook-health standalone prints the warning without a transcript"
HH_CLEAN="$(AGENT_TEAM_PROFILE="$HEALTHY" python3 "$TOOL" --hook-health 2>/dev/null)"
if [ -z "$HH_CLEAN" ]; then
  pass "--hook-health is silent on a healthy profile"
else
  fail "--hook-health is silent on a healthy profile — got: $HH_CLEAN"
fi

# --- (g2) proportionality: trivial dispatches on non-cheapest models -------
# The good fixture's two subagents each made 2 unique requests on opus/sonnet:
# both are trivial dispatches on non-cheapest models and must be flagged.
expect_contains "$MD" "Proportionality: 2 trivial dispatch" \
  "trivial opus+sonnet dispatches are flagged"
expect_contains "$MD" "(bbbb2222): 2 requests on claude-sonnet-5" \
  "flag names the dispatch, request count, and model"
expect_contains "$MD" "(aaaa1111): 2 requests on claude-opus-4-8" \
  "opus trivial dispatch is flagged too"
expect_contains "$MD" "cheapest capable model" \
  "flag cites the charter rule"
# Trivial-on-haiku and non-trivial-on-sonnet both draw no flag.
PROP_DIR="$TMP/proportional-run"
mkdir -p "$PROP_DIR/session/subagents"
PROP_MAIN="$PROP_DIR/session.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-07-22T00:00:00.000Z","message":{"id":"msg_m1","model":"claude-opus-4-8","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' > "$PROP_MAIN"
printf '%s\n' '{"type":"assistant","timestamp":"2026-07-22T00:00:01.000Z","message":{"id":"msg_h1","model":"claude-haiku-4-5","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":50,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}' > "$PROP_DIR/session/subagents/agent-cccc3333.jsonl"
for i in 1 2 3 4; do
  printf '{"type":"assistant","timestamp":"2026-07-22T00:00:0%s.000Z","message":{"id":"msg_s%s","model":"claude-sonnet-5","content":[{"type":"text","text":"work"}],"usage":{"input_tokens":50,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' "$i" "$i"
done > "$PROP_DIR/session/subagents/agent-dddd4444.jsonl"
PROP_MD="$(python3 "$TOOL" --transcript "$PROP_MAIN" 2>/dev/null)"
expect_not_contains "$PROP_MD" "Proportionality:" \
  "haiku-trivial and sonnet-4-request dispatches draw no flag"

# --- (g) rates staleness note ---
OLD_RATES="$TMP/old-rates.json"
jq '.as_of = "2026-01-01"' "$ROOT/hooks/model-rates.json" > "$OLD_RATES"
STALE_MD="$(python3 "$TOOL" --transcript "$FIXTURE" --rates "$OLD_RATES" 2>/dev/null)"
expect_contains "$STALE_MD" "days old" "stale rates file gets a staleness note"
expect_not_contains "$MD" "days old" "fresh rates file carries no staleness note"

echo "cost-report tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
