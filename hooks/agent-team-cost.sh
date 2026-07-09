#!/usr/bin/env bash
# agent-team-cost.sh — PostToolUse(Agent) hook: sums exact per-request token
# usage from this session's per-dispatch subagent transcripts into a per-session
# cost file, priced from model-rates.json. Never blocks, never emits a wrong
# number: on any unrecognized input it writes a sticky "unavailable" marker and
# exits 0. See docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md.
set -u

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.tool_response.agentId // empty')"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.tool_response.agentType // "unknown"')"

# Cannot even locate a cost file safely -> write nothing, exit 0.
[ -n "$SESSION_ID" ] || exit 0
[ -n "$TRANSCRIPT" ] || exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
RATES="${AGENT_TEAM_RATES:-$HERE/model-rates.json}"
COST_DIR="${AGENT_TEAM_COST_DIR:-$HOME/.claude/logs/agent-team-cost}"
SUBAGENTS_DIR="${TRANSCRIPT%.jsonl}/subagents"
SLUG="$(printf '%s' "$CWD" | tr '/' '-')"
COST_FILE="$COST_DIR/$SLUG--$SESSION_ID.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$COST_DIR"

# write_unavailable REASON -> sticky marker, exit 0.
write_unavailable() {
  printf '%s' "$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" --arg r "$1" \
    '{version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"unavailable", unavailable_reason:$r}')" \
    > "$COST_FILE"
  exit 0
}

# --- minimal for Task 3: write an empty ok document. Filled in by later tasks. ---
printf '%s' "$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" \
  '{version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"ok",
    dispatches:{}, totals:{models:{}, cost_usd:0, web_search_requests:0, web_fetch_requests:0}}')" \
  > "$COST_FILE"
exit 0
