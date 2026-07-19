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
readonly BUDGETS_FILE="$(cd "$(dirname "$0")" && pwd)/agent-team-budgets.json"
readonly DEFAULT_DISPATCH_CHECKPOINT=10

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

# T12: dispatch-count budget ratchet. Missing/invalid config fails to the
# strict side (checkpoint 10). Count is ALL Agent dispatches so far
# (resolved + unresolved) in the transcript; this incoming dispatch would be
# the next one, so a count of N*checkpoint-1 means this IS the N*checkpoint'th
# dispatch. Stateless by design: no mutable counter file, the transcript is
# ground truth every time.
DISPATCH_CHECKPOINT="$DEFAULT_DISPATCH_CHECKPOINT"
if [ -f "$BUDGETS_FILE" ]; then
  CONFIGURED="$(jq -r '.dispatch_checkpoint // empty' "$BUDGETS_FILE" 2>/dev/null)"
  case "$CONFIGURED" in
    ''|*[!0-9]*) ;;
    *) DISPATCH_CHECKPOINT="$CONFIGURED" ;;
  esac
fi

TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ "$DISPATCH_CHECKPOINT" -gt 0 ]; then
  PRIOR_COUNT="$(
    jq -rs '
      reduce .[] as $line (0;
        ($line.message.content // [])[] as $block
        | if ($block.type == "tool_use" and $block.name == "Agent") then . + 1 else . end
      )
    ' "$TRANSCRIPT" 2>/dev/null
  )"
  case "$PRIOR_COUNT" in ''|*[!0-9]*) PRIOR_COUNT=0 ;; esac
  THIS_DISPATCH_NUMBER=$((PRIOR_COUNT + 1))
  if [ "$((THIS_DISPATCH_NUMBER % DISPATCH_CHECKPOINT))" -eq 0 ]; then
    PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
    case "$PROMPT" in
      *"WORKFORCE_BUDGET_ACK: $THIS_DISPATCH_NUMBER dispatches"*) ;;
      *)
        printf 'agent-team dispatch guard: this is dispatch #%s — a checkpoint (every %s). Re-triage before continuing: include the exact prompt line "WORKFORCE_BUDGET_ACK: %s dispatches — continuing because <tier and why proportionate>" to proceed.\n' "$THIS_DISPATCH_NUMBER" "$DISPATCH_CHECKPOINT" "$THIS_DISPATCH_NUMBER" >&2
        exit 2
        ;;
    esac
  fi
fi

exit 0
