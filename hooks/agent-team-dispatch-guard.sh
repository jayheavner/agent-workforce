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

readonly VALID_SPECIALISTS="architect builder debugger verifier reviewer deployer executor researcher ops scribe ticketer"
# Git-mutating dispatches are serialized per checkout; MUTATING_ROLES in the
# closeout hook serves baseline-capture logic and is a different set — do not
# conflate the two.
readonly GIT_SERIALIZED_ROLES="builder executor deployer"
readonly PARALLEL_SAFE_MARKER="PARALLEL_SAFE: no git mutation in this dispatch"
readonly RESEARCH_ONLY_MARKER="RESEARCH_ONLY: sources provided in prompt"
# Present-state shell verification (git, running processes, live transcripts)
# has no seam for the shell-less researcher to observe — route it to the
# executor, or use the marker for genuine source-analysis research.
readonly RESEARCHER_SHELL_VERB_PATTERN='git |rev-parse|merge-base|run the|execute|parse the.*transcript|\.jsonl'

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
  printf 'agent-team dispatch guard: this Agent dispatch has no subagent_type. Every dispatch MUST set subagent_type to exactly one of: architect, builder, debugger, verifier, reviewer, deployer, executor, researcher, ops, scribe, ticketer. Re-issue the dispatch with an explicit subagent_type.\n' >&2
  exit 2
fi

# Direct plugin loading namespaces component names. Accept this plugin's own
# namespace and normalize it for the exact specialist allowlist below; no
# other namespace is trusted.
case "$TYPE" in
  agent-workforce:*) TYPE="${TYPE#agent-workforce:}" ;;
  *:*)
    printf 'agent-team dispatch guard: subagent_type belongs to an unrecognized plugin namespace. Use an agent-workforce specialist.\n' >&2
    exit 2
    ;;
esac

# Exact equality against each of the ten names only — no substring/containment
# matching, so a compound value like "architect builder" cannot bypass by
# matching two adjacent tokens in a space-padded list.
VALID=0
for name in $VALID_SPECIALISTS; do
  if [ "$TYPE" = "$name" ]; then
    VALID=1
    break
  fi
done

if [ "$VALID" -ne 1 ]; then
  printf 'agent-team dispatch guard: subagent_type "%s" is not a team specialist. Use exactly one of: architect, builder, debugger, verifier, reviewer, deployer, executor, researcher, ops, scribe, ticketer. (The harness default "general-purpose" is not a team agent and will hard-fail.)\n' "$TYPE" >&2
  exit 2
fi

# T11: the researcher has no shell — block prompts asking for present-state
# shell verification (git, running processes, live transcripts) unless the
# dispatch is genuine document analysis of material already in the prompt.
if [ "$TYPE" = "researcher" ]; then
  PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
  case "$PROMPT" in
    *"$RESEARCH_ONLY_MARKER"*) ;;
    *)
      if printf '%s' "$PROMPT" | grep -qiE "$RESEARCHER_SHELL_VERB_PATTERN"; then
        printf 'agent-team dispatch guard: researcher has no shell — route present-state verification to the executor, or include `%s` if this is document analysis of provided material.\n' "$RESEARCH_ONLY_MARKER" >&2
        exit 2
      fi
      ;;
  esac
fi

# T6: serialize git-mutating dispatches ({builder, executor, deployer}) per
# checkout. Only these roles are policed; skip the scan entirely otherwise.
IS_SERIALIZED_ROLE=0
for name in $GIT_SERIALIZED_ROLES; do
  if [ "$TYPE" = "$name" ]; then
    IS_SERIALIZED_ROLE=1
    break
  fi
done

if [ "$IS_SERIALIZED_ROLE" -eq 1 ]; then
  PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
  case "$PROMPT" in
    *"$PARALLEL_SAFE_MARKER"*) exit 0 ;;
  esac
  TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    UNRESOLVED_ROLE="$(
      jq -rs --arg roles "$GIT_SERIALIZED_ROLES" '
        ($roles | split(" ")) as $serialized
        | reduce .[] as $line ({};
            ($line.message.content // [])[] as $block
            | if ($block.type == "tool_use" and $block.name == "Agent")
              then .[$block.id] = ($block.input.subagent_type // "")
              elif ($block.type == "tool_result" and $block.tool_use_id != null)
              then del(.[$block.tool_use_id])
              else . end
          )
        | to_entries[]
        | select(.value as $r | $serialized | index($r))
        | .value
      ' "$TRANSCRIPT" 2>/dev/null | head -n1
    )"
    if [ -n "$UNRESOLVED_ROLE" ]; then
      printf 'agent-team dispatch guard: serialize git-mutating dispatches: %s still in flight. Wait for it to resolve, or include the exact prompt line "%s" if this dispatch makes no git mutation.\n' "$UNRESOLVED_ROLE" "$PARALLEL_SAFE_MARKER" >&2
      exit 2
    fi
  fi
fi

exit 0
