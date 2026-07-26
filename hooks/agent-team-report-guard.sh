#!/usr/bin/env bash
# agent-team-report-guard.sh — specialist-side Stop hook (auto-converted to
# SubagentStop when the specialist runs as a dispatched subagent; the payload
# then carries the subagent's own last_assistant_message and agent_type).
#
# Enforces the report contract at the source: a specialist may not finish
# until its final message ends with a WORKFORCE_REPORT marker line (within
# the last three non-empty lines, leaving room for the Codex
# WORKFORCE_PROFILE final line). This closes the async gap mechanically —
# the guard runs at the specialist's own stop, before the parent consumes
# anything, so background dispatches are covered the same as sync ones. A
# KILLED agent (turn cap, crash) fires no hooks; that case remains detected
# at the consumption point (agent-team-interrupt-guard.sh and the Codex
# dispatcher). See docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md.
#
# Never wedges: stop_hook_active means we already blocked once this stop —
# fail open. Unparseable input, missing jq, or an absent message also allow.
# Block shape is the documented Stop-decision JSON on stdout, exit 0.
set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)" || exit 0
[ -n "$PARSED" ] || exit 0

# Already blocked once for this stop -> the specialist either complied (the
# marker check below would pass anyway) or genuinely cannot; let it finish.
ACTIVE="$(printf '%s' "$PARSED" | jq -r '(.stop_hook_active // false) | tostring')"
[ "$ACTIVE" = "true" ] && exit 0

MSG="$(printf '%s' "$PARSED" | jq -r '.last_assistant_message // ""')"
[ -n "$MSG" ] || exit 0

TAIL="$(printf '%s' "$MSG" | grep -v '^[[:space:]]*$' | tail -n 3)"
case "$TAIL" in
  *"WORKFORCE_REPORT:"*) exit 0 ;;
esac

ROLE="$(printf '%s' "$PARSED" | jq -r '.agent_type // "specialist"')"
ROLE="${ROLE##*:}"

jq -cn --arg role "$ROLE" '{decision:"block", reason:("Your report is missing its final contract line. End your final message with `WORKFORCE_REPORT: " + $role + " | complete|partial|blocked` — complete only if the dispatched scope is delivered with evidence; partial for a deliberate early stop with what-stands/what-remains; blocked for a typed blocker. Re-state your report now with that final line. Without it the orchestrator must treat your dispatch as cut off mid-work.")}'
exit 0
