#!/usr/bin/env bash
# agent-team-interrupt-guard.sh — PostToolUse(Agent) guard for the
# orchestrator: detects a dispatch that returned WITHOUT its report contract.
#
# Every specialist report must end with a WORKFORCE_REPORT marker line (within
# the last three non-empty lines). A turn-capped, context-exhausted, or
# crashed agent physically cannot emit its final message, so the marker's
# ABSENCE is a mechanical truncation signal: the dispatch must be treated as
# interrupted work, never as a completed phase. (The marker's VALUE is
# advisory — actual completion is still judged by the acceptance criteria,
# verifier, and reviewer — so rote compliance in the emitted value gains
# nothing. See docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md §3.)
#
# Advisory guard, so it fails OPEN: it runs after the call and cannot undo it,
# only inform the orchestrator. Unparseable input, a missing jq, an async
# launch stub, or a non-Agent tool all exit 0. Exit 2 = feed the
# reconcile-and-resume protocol back to the orchestrator via stderr.
set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)" || exit 0
[ -n "$PARSED" ] || exit 0

TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty')"
[ "$TOOL" = "Agent" ] || exit 0

# Async launch stubs carry no report; completion arrives later as a
# task-notification (the orchestrator contract applies the same
# missing-marker rule there by instruction).
IS_ASYNC="$(printf '%s' "$PARSED" | jq -r '(.tool_response.isAsync // false) | tostring')"
STATUS="$(printf '%s' "$PARSED" | jq -r '.tool_response.status // empty')"
if [ "$IS_ASYNC" = "true" ] || [ "$STATUS" = "async_launched" ]; then
  exit 0
fi

# Join the report text: content is an array of text blocks on real results;
# accept a plain string defensively. Anything else -> empty.
TEXT="$(printf '%s' "$PARSED" | jq -r '
  .tool_response.content
  | if type == "array" then (map(.text // "") | join("\n"))
    elif type == "string" then .
    else "" end' 2>/dev/null)"

ROLE="$(printf '%s' "$PARSED" | jq -r '.tool_input.subagent_type // "specialist"')"

# Marker must sit in the last three non-empty lines (leaving room for the
# Codex WORKFORCE_PROFILE final line).
TAIL="$(printf '%s' "$TEXT" | grep -v '^[[:space:]]*$' | tail -n 3)"
case "$TAIL" in
  *"WORKFORCE_REPORT:"*) exit 0 ;;
esac

printf 'agent-team interrupt guard: the %s dispatch returned without a WORKFORCE_REPORT marker in its final lines — treat it as interrupted (turn cap, context exhaustion, or crash), NOT as a completed phase and NOT as a blocker report. Do not advance the route on its partial output. Reconcile and resume: (1) inspect the workspace read-only — git log/status for its commits, test state, files touched; (2) re-dispatch the same role with what verifiably stands, the remaining ACCEPTANCE CRITERIA, and the word RESUME in the prompt; (3) after two interrupted resumes of the same phase, stop and escalate to the human with the evidence.\n' "$ROLE" >&2
exit 2
