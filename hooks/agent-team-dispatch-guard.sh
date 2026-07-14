#!/usr/bin/env bash
# agent-team-dispatch-guard.sh — PreToolUse(Agent) guard for the orchestrator.
# Blocks any Agent dispatch whose subagent_type is missing, empty, or not one
# of the ten named team specialists (so a forgotten field can never default to
# 'general-purpose' and stall the task silently).
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr returned to agent).
#
# Fail-closed by design: this is a safety guard, so any condition that leaves
# it unable to positively confirm "not an Agent dispatch" or "a valid
# specialist" results in a block, never a silent allow.
set -u

readonly VALID_SPECIALISTS="architect builder debugger verifier reviewer deployer researcher ops scribe ticketer"

if ! command -v jq >/dev/null 2>&1; then
  printf 'agent-team dispatch guard: jq is not available, so this guard cannot parse the dispatch payload. Blocking rather than failing open.\n' >&2
  exit 2
fi

INPUT="$(cat)"

# Parse stdin exactly once and check jq's own exit status. If stdin is not
# valid JSON (or is empty), jq fails and we must block — an empty tool_name
# derived from a failed parse must never be read as "not Agent, so allow".
PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)"
if [ $? -ne 0 ] || [ -z "$PARSED" ]; then
  printf 'agent-team dispatch guard: stdin was not valid JSON, so this dispatch cannot be verified. Blocking rather than failing open.\n' >&2
  exit 2
fi

TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty')"

# Only police Agent dispatches; anything else passes through untouched.
[ "$TOOL" = "Agent" ] || exit 0

TYPE="$(printf '%s' "$PARSED" | jq -r '.tool_input.subagent_type // empty')"

if [ -z "$TYPE" ]; then
  printf 'agent-team dispatch guard: this Agent dispatch has no subagent_type. Every dispatch MUST set subagent_type to exactly one of: architect, builder, debugger, verifier, reviewer, deployer, researcher, ops, scribe, ticketer. Re-issue the dispatch with an explicit subagent_type.\n' >&2
  exit 2
fi

# Exact equality against each of the ten names only — no substring/containment
# matching, so a compound value like "architect builder" cannot bypass by
# matching two adjacent tokens in a space-padded list.
for name in $VALID_SPECIALISTS; do
  if [ "$TYPE" = "$name" ]; then
    exit 0
  fi
done

printf 'agent-team dispatch guard: subagent_type "%s" is not a team specialist. Use exactly one of: architect, builder, debugger, verifier, reviewer, deployer, researcher, ops, scribe, ticketer. (The harness default "general-purpose" is not a team agent and will hard-fail.)\n' "$TYPE" >&2
exit 2
