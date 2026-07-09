#!/usr/bin/env bash
# agent-team-dispatch-guard.sh — PreToolUse(Agent) guard for the orchestrator.
# Blocks any Agent dispatch whose subagent_type is missing, empty, or not one
# of the nine named team specialists (so a forgotten field can never default to
# 'general-purpose' and stall the task silently).
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr returned to agent).
set -u

VALID=" architect builder verifier reviewer deployer researcher ops scribe ticketer "

INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"

# Only police Agent dispatches; anything else passes through untouched.
[ "$TOOL" = "Agent" ] || exit 0

TYPE="$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty')"

if [ -z "$TYPE" ]; then
  printf 'agent-team dispatch guard: this Agent dispatch has no subagent_type. Every dispatch MUST set subagent_type to exactly one of: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer. Re-issue the dispatch with an explicit subagent_type.\n' >&2
  exit 2
fi

case "$VALID" in
  *" $TYPE "*) exit 0 ;;
  *)
    printf 'agent-team dispatch guard: subagent_type "%s" is not a team specialist. Use exactly one of: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer. (The harness default "general-purpose" is not a team agent and will hard-fail.)\n' "$TYPE" >&2
    exit 2
    ;;
esac
