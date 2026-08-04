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

readonly VALID_SPECIALISTS="architect builder debugger verifier reviewer deployer executor researcher ops scribe ticketer test-author"
# Git-mutating dispatches are policed per TARGET, not per role: a dispatch that
# declares its own worktree collides only with another live dispatch in the
# same worktree, so builders in distinct worktrees run concurrently
# (policy:workspace-isolation). A git-mutating dispatch that declares nothing
# still serializes — an undeclared target cannot be proven disjoint from the
# shared checkout. MUTATING_ROLES in the closeout hook serves baseline-capture
# logic and is a different set — do not conflate the two.
readonly GIT_SERIALIZED_ROLES="builder executor deployer test-author"
# Roles that MUST declare a worktree: the policy gives every builder its own.
readonly WORKTREE_REQUIRED_ROLES="builder"
readonly WORKTREE_MARKER_PREFIX="WORKTREE:"
readonly PARALLEL_SAFE_MARKER="PARALLEL_SAFE: no git mutation in this dispatch"
readonly BUDGETS_FILE="$(cd "$(dirname "$0")" && pwd)/agent-team-budgets.json"
readonly LANES_FILE="$(cd "$(dirname "$0")" && pwd)/agent-team-lanes.json"
# A specialist that refuses work as outside its lane says so in a line the
# orchestrator cannot reinterpret. The 2026-08-03 incident turned on a correct
# refusal arriving as prose: the scribe declined source-and-test work, and the
# orchestrator read the refusal as "find a wider tool" rather than "wrong role."
# A typed refusal lets this guard challenge the re-route mechanically.
readonly REFUSAL_MARKER="WORKFORCE_REFUSAL: out-of-lane"
# A refusal can itself be wrong. On 2026-08-04 a lane guard defect refused an
# architect its own plan; the rule below then made that false refusal permanent
# routing law, and the only role it could still be routed to was disabled by a
# second defect — five attempts with no way out, because the guard treated a
# refusal as necessarily correct. The escape is the human's and only the human's:
# the marker counts when it appears in the human's own turn of the session
# transcript, never in an assistant turn and never inside a subagent's report,
# because an orchestrator that can clear its own refusals is not being held to
# anything. Every use is recorded as a fail-open — a control that stopped
# enforcing must never be quieter than one that held.
readonly OVERRIDE_MARKER="WORKFORCE_OVERRIDE: lane-refusal"
# shellcheck source=/dev/null
[ -r "$(dirname "$0")/agent-team-guard-log.sh" ] && . "$(dirname "$0")/agent-team-guard-log.sh"
command -v guard_log >/dev/null 2>&1 || guard_log() { :; }

readonly DEFAULT_DISPATCH_CHECKPOINT=10

if ! command -v jq >/dev/null 2>&1; then
  guard_log dispatch "${TYPE:-unknown}" block "jq unavailable"
  printf 'agent-team dispatch guard: jq is not available, so this guard cannot parse the dispatch payload. Blocking rather than failing open.\n' >&2
  exit 2
fi

INPUT="$(cat)"

# Parse stdin exactly once and check jq's own exit status. If stdin is not
# valid JSON (or is empty), jq fails and we must block — an empty tool_name
# derived from a failed parse must never be read as "not Agent, so allow".
PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)"
if [ $? -ne 0 ] || [ -z "$PARSED" ]; then
  guard_log dispatch "${TYPE:-unknown}" block "invalid payload"
  printf 'agent-team dispatch guard: stdin was not valid JSON, so this dispatch cannot be verified. Blocking rather than failing open.\n' >&2
  exit 2
fi

TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty')"

# Only police Agent dispatches; anything else passes through untouched.
[ "$TOOL" = "Agent" ] || exit 0

TYPE="$(printf '%s' "$PARSED" | jq -r '.tool_input.subagent_type // empty')"

if [ -z "$TYPE" ]; then
  guard_log dispatch "$TYPE" block "no subagent_type"
  printf 'agent-team dispatch guard: this Agent dispatch has no subagent_type. Every dispatch MUST set subagent_type to exactly one of: architect, builder, debugger, verifier, reviewer, deployer, executor, researcher, ops, scribe, ticketer. Re-issue the dispatch with an explicit subagent_type.\n' >&2
  exit 2
fi

# Direct plugin loading namespaces component names. Accept this plugin's own
# namespace and normalize it for the exact specialist allowlist below; no
# other namespace is trusted.
case "$TYPE" in
  agent-workforce:*) TYPE="${TYPE#agent-workforce:}" ;;
  *:*)
    guard_log dispatch "$TYPE" block "unrecognized plugin namespace"
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
  guard_log dispatch "$TYPE" block "not a specialist"
  printf 'agent-team dispatch guard: subagent_type "%s" is not a team specialist. Use exactly one of: architect, builder, debugger, verifier, reviewer, deployer, executor, researcher, ops, scribe, ticketer. (The harness default "general-purpose" is not a team agent and will hard-fail.)\n' "$TYPE" >&2
  exit 2
fi

# Criteria-before-code (2026-07-26 checks-balances spec §1): builder and
# verifier dispatches must carry an ACCEPTANCE CRITERIA block, authored by the
# orchestrator from the plan or the original request — the builder's own tests
# are never the definition of done, and the verifier judges the same criteria
# the builder was given, verbatim. The block is held to the SAME
# falsifiability lint plans are held to (lint_acceptance_checks.py): at least
# one tagged criterion, zero BLOCK findings. Marker presence alone is a
# checkbox and does not pass.
CRITERIA_SHAPE='  - [ ] AC-N (mechanical): <claim>. Check: `<command that can fail and prints why>` -> expects <observable>.
  - [ ] AC-N (judgment): <claim>. Judge: <who>. Bar: <what a "no" looks like>.'
case "$TYPE" in
  builder|verifier|test-author)
    PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
    case "$PROMPT" in
      *"ACCEPTANCE CRITERIA"*) : ;;
      *)
        guard_log dispatch "$TYPE" block "no acceptance criteria"
        printf 'agent-team dispatch guard: a %s dispatch must carry an "ACCEPTANCE CRITERIA" block. Author the criteria BEFORE the code exists — from the architect plan when one ran, from the original request otherwise — and pass the identical block to both the builder and the verifier. The builder'"'"'s own tests are scaffolding for its red/green loop, never the bar. Criterion shape:\n%s\nRe-issue this dispatch with the criteria included.\n' "$TYPE" "$CRITERIA_SHAPE" >&2
        exit 2
        ;;
    esac
    # Falsifiability lint. Installed: ships beside this guard in the hooks
    # dir. Repo checkout: lives in the sibling tools/ dir. Its absence means
    # a broken install and this guard fails closed rather than degrading to a
    # string match.
    GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
    LINT="$GUARD_DIR/lint_acceptance_checks.py"
    [ -f "$LINT" ] || LINT="$GUARD_DIR/../tools/lint_acceptance_checks.py"
    if [ ! -f "$LINT" ]; then
      guard_log dispatch "$TYPE" block "acceptance lint missing"
      printf 'agent-team dispatch guard: lint_acceptance_checks.py is missing beside this guard — the install is incomplete, so criteria quality cannot be verified. Blocking rather than failing open; run bash install.sh from the workforce repo.\n' >&2
      exit 2
    fi
    CRITERIA_FILE="$(mktemp "${TMPDIR:-/tmp}/dispatch-criteria.XXXXXX")"
    printf '%s\n' "$PROMPT" | sed -n '/ACCEPTANCE CRITERIA/,$p' > "$CRITERIA_FILE"
    LINT_OUT="$(python3 "$LINT" "$CRITERIA_FILE" 2>&1)"
    LINT_RC=$?
    rm -f "$CRITERIA_FILE"
    if [ "$LINT_RC" -eq 1 ]; then
      guard_log dispatch "$TYPE" block "acceptance criteria failed the lint"
      printf 'agent-team dispatch guard: the ACCEPTANCE CRITERIA block in this %s dispatch failed the falsifiability lint:\n%s\nFix the flagged criteria (each finding names the repair) and re-issue the dispatch.\n' "$TYPE" "$LINT_OUT" >&2
      exit 2
    fi
    case "$LINT_OUT" in
      *"no tagged acceptance criteria found"*)
        guard_log dispatch "$TYPE" block "no tagged acceptance criterion"
        printf 'agent-team dispatch guard: the ACCEPTANCE CRITERIA block in this %s dispatch contains no tagged criterion, so nothing in it is checkable. Write at least one criterion in the shape:\n%s\nRe-issue the dispatch with real criteria.\n' "$TYPE" "$CRITERIA_SHAPE" >&2
        exit 2
        ;;
    esac
    ;;
esac

# --- Re-routing a typed lane refusal to the wrong role.
# When a specialist has refused a path as outside its lane, the next dispatch
# carrying that same path must go to the role whose lane covers it. Anything else
# is the incident's exact move: a refusal treated as license to widen.
lane_owner() { # $1 repo-relative path -> the role whose lane owns it
  local owner=""
  if [ -f "$LANES_FILE" ]; then
    owner="$(jq -r --arg p "$1" '
      (.role_lanes // {}) | to_entries
      | map(select(.value | type == "array" and any(
            . as $l | ($l | tostring | sub("/+$"; "")) as $lane
            | $p == $lane or ($p | startswith($lane + "/")))))
      | if length == 0 then "" else (.[0].key) end
    ' "$LANES_FILE" 2>/dev/null)"
  fi
  # Nothing else claims it, so it is source or tests: the builder's.
  [ -n "$owner" ] || owner="builder"
  printf '%s' "$owner"
}

# Paths the human has released, one per line. Only a human turn counts: an entry
# the transcript marks as the user's whose content is plain text. A tool result is
# also recorded as a user entry — that is how a subagent's report arrives — so
# anything carrying a tool_result block or a tool-use result is excluded, and
# assistant turns are never read at all.
human_override_paths() { # -> released paths, one per line
  jq -rs --arg m "$OVERRIDE_MARKER" '
    [ .[]
      | select(.type == "user" and (has("toolUseResult") | not))
      | .message.content
      | if type == "string" then .
        elif type == "array" then
          (if any(.[]; .type != "text") then empty
           else (map(.text // "") | join("\n")) end)
        else empty end
      | [ splits("\n") ]
      | map(select(startswith($m)))
      | .[]
      | ltrimstr($m) | ltrimstr(" ") | ltrimstr("|")
    ] | unique | .[]
  ' "$TRANSCRIPT" 2>/dev/null \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[`"'"'"']//g'
}

TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
  CWD="$(printf '%s' "$PARSED" | jq -r '.cwd // empty')"
  OVERRIDDEN="$(human_override_paths)"
  ROOT=""
  [ -n "$CWD" ] && [ -d "$CWD" ] && ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  REFUSED="$(jq -rs --arg m "$REFUSAL_MARKER" '
    [ .[] | .. | strings | select(contains($m))
      | [ splits("\n") ] | map(select(contains($m))) | .[] ]
    | unique | .[]
  ' "$TRANSCRIPT" 2>/dev/null)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    refused_path="${line#*"$REFUSAL_MARKER"}"
    refused_path="${refused_path#*|}"
    refused_path="$(printf '%s' "$refused_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[`"'"'"']//g')"
    [ -n "$refused_path" ] || continue
    case "$PROMPT" in *"$refused_path"*) ;; *) continue ;; esac
    released=0
    while IFS= read -r allowed; do
      [ -n "$allowed" ] || continue
      [ "$allowed" = "$refused_path" ] && { released=1; break; }
    done <<EOF
$OVERRIDDEN
EOF
    if [ "$released" -eq 1 ]; then
      guard_log dispatch "$TYPE" fail-open "human override of lane refusal for $refused_path"
      continue
    fi
    rel="$refused_path"
    if [ -n "$ROOT" ]; then
      case "$rel" in "$ROOT"/*) rel="${rel#"$ROOT"/}" ;; esac
    fi
    owner="$(lane_owner "$rel")"
    if [ "$TYPE" != "$owner" ]; then
      printf 'agent-team dispatch guard: %s was already refused as out of lane by another specialist, and this dispatch routes it to the %s. A lane refusal is a routing correction, never permission to widen: %s belongs to the %s. Re-dispatch it there, or drop that path from this dispatch if the work genuinely differs.\nIf you believe the refusal itself was wrong, say so and stop — only your human can release a path, by writing this line in their own message:\n  %s | <path>\nDo not write that line yourself; a line authored by you is not read as an override.\n' \
        "$refused_path" "$TYPE" "$rel" "$owner" "$OVERRIDE_MARKER" >&2
      guard_log dispatch "$TYPE" block "reroute of refused $rel"
      exit 2
    fi
  done <<EOF
$REFUSED
EOF
fi

# Workspace isolation for git-mutating dispatches ({builder, executor,
# deployer, test-author}). Only these roles are policed; skip the scan entirely
# otherwise.
IS_SERIALIZED_ROLE=0
for name in $GIT_SERIALIZED_ROLES; do
  if [ "$TYPE" = "$name" ]; then
    IS_SERIALIZED_ROLE=1
    break
  fi
done

# Normalize a declared worktree path for comparison: trim surrounding blanks
# and any trailing slashes, so ".../wt", ".../wt/" and ".../wt  " are one
# directory. Purely textual — the path need not exist yet, since the builder
# creates it.
normalize_worktree() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's:/*$::'
}

if [ "$IS_SERIALIZED_ROLE" -eq 1 ]; then
  PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
  case "$PROMPT" in
    *"$PARALLEL_SAFE_MARKER"*) exit 0 ;;
  esac

  # The worktree this dispatch declares for itself, if any.
  DECLARED_WORKTREE="$(normalize_worktree "$(
    printf '%s\n' "$PROMPT" | sed -n "s/^[[:space:]]*${WORKTREE_MARKER_PREFIX}[[:space:]]*//p" | head -n1
  )")"

  WORKTREE_REQUIRED=0
  for name in $WORKTREE_REQUIRED_ROLES; do
    if [ "$TYPE" = "$name" ]; then
      WORKTREE_REQUIRED=1
      break
    fi
  done

  if [ "$WORKTREE_REQUIRED" -eq 1 ] && [ -z "$DECLARED_WORKTREE" ]; then
    guard_log dispatch "$TYPE" block "no worktree declared"
    printf 'agent-team dispatch guard: a %s dispatch must declare its own unique worktree. policy:workspace-isolation gives every builder a private git worktree created before any code is touched, and this guard cannot prove two builders are disjoint without the declaration. Add one line to the dispatch:\n  %s <project>/.claude/worktrees/<task-slug>-<builder-instance>\nUse a path no other live dispatch is using, and never the parent checkout.\n' \
      "$TYPE" "$WORKTREE_MARKER_PREFIX" >&2
    exit 2
  fi

  # A builder never works in the parent checkout. Enforced only when the
  # harness supplies cwd; absence leaves the rule unenforced, not inverted.
  if [ -n "$DECLARED_WORKTREE" ]; then
    CWD="$(printf '%s' "$PARSED" | jq -r '.cwd // empty')"
    if [ -n "$CWD" ] && [ -d "$CWD" ]; then
      CHECKOUT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
      if [ "$(normalize_worktree "$CHECKOUT_ROOT")" = "$DECLARED_WORKTREE" ]; then
        guard_log dispatch "$TYPE" block "declared the parent checkout: $DECLARED_WORKTREE"
        printf 'agent-team dispatch guard: this %s dispatch declares the parent checkout (%s) as its worktree. policy:workspace-isolation forbids a builder editing the shared checkout — create a separate worktree under %s/.claude/worktrees/ and declare that path instead.\n' \
          "$TYPE" "$DECLARED_WORKTREE" "$CHECKOUT_ROOT" >&2
        exit 2
      fi
    fi
  fi

  TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # Background dispatches: the immediate tool_result is a launch stub
    # ("Async agent launched successfully"); the dispatch is only resolved by
    # a later task-notification carrying its tool_use id. A stub therefore
    # does NOT clear in-flight status; a notification does.
    # One "<role><TAB><declared worktree>" line per still-in-flight
    # git-mutating dispatch. The worktree is read from that dispatch's own
    # prompt, so uniqueness is judged against what each builder was actually
    # told to use.
    UNRESOLVED_TARGETS="$(
      jq -rs --arg roles "$GIT_SERIALIZED_ROLES" --arg marker "$WORKTREE_MARKER_PREFIX" '
        ($roles | split(" ")) as $serialized
        | ([ .[] | .. | strings
             | match("<tool-use-id>([^<]+)</tool-use-id>"; "g")
             | .captures[0].string ] | unique) as $notified
        | reduce .[] as $line ({};
            ((($line.message.content // []) | if type == "array" then . else [] end))[] as $block
            | if ($block.type == "tool_use" and $block.name == "Agent")
              then .[$block.id] = {
                     role: ($block.input.subagent_type // ""),
                     worktree: (
                       ($block.input.prompt // "")
                       | [ splits("\n") ]
                       | map(select(startswith($marker)))
                       | if length == 0 then "" else (.[0] | ltrimstr($marker)) end
                     )
                   }
              elif ($block.type == "tool_result" and $block.tool_use_id != null
                    and (([$block.content] | flatten
                          | map(if type == "object" then (.text // "") else tostring end)
                          | join(" "))
                         | contains("Async agent launched successfully") | not))
              then del(.[$block.tool_use_id])
              else . end
          )
        | to_entries[]
        | select((.key as $k | $notified | index($k) | not)
                 and (.value.role as $r | $serialized | index($r)))
        | "\(.value.role)\t\(.value.worktree)"
      ' "$TRANSCRIPT" 2>/dev/null
    )"

    if [ -n "$UNRESOLVED_TARGETS" ]; then
      if [ -n "$DECLARED_WORKTREE" ]; then
        # Declared target: the only conflict is another live dispatch in the
        # SAME worktree. Distinct worktrees are what makes concurrent builders
        # legal, so they pass here.
        while IFS="$(printf '\t')" read -r other_role other_wt; do
          [ -n "$other_role" ] || continue
          [ -n "$other_wt" ] || continue
          if [ "$(normalize_worktree "$other_wt")" = "$DECLARED_WORKTREE" ]; then
            guard_log dispatch "$TYPE" block "worktree collision: $DECLARED_WORKTREE"
            printf 'agent-team dispatch guard: worktree collision: a %s dispatch is still in flight in %s, and no two dispatches may share a worktree (policy:workspace-isolation). Give this %s its own path — %s <project>/.claude/worktrees/<task-slug>-<builder-instance> — or wait for the other dispatch to resolve if this work must follow it.\n' \
              "$other_role" "$DECLARED_WORKTREE" "$TYPE" "$WORKTREE_MARKER_PREFIX" >&2
            exit 2
          fi
        done <<EOF
$UNRESOLVED_TARGETS
EOF
      else
        # Undeclared target: cannot be proven disjoint from the shared
        # checkout, so the old serialization still applies.
        FIRST_ROLE="$(printf '%s\n' "$UNRESOLVED_TARGETS" | head -n1 | cut -f1)"
        guard_log dispatch "$TYPE" block "undeclared target serialized behind $FIRST_ROLE"
        printf 'agent-team dispatch guard: this %s dispatch declares no worktree, so it is treated as mutating the shared checkout, and a %s dispatch is still in flight. Wait for it to resolve, declare a %s path this dispatch owns, or include the exact prompt line "%s" if this dispatch makes no git mutation.\n' \
          "$TYPE" "$FIRST_ROLE" "$WORKTREE_MARKER_PREFIX" "$PARALLEL_SAFE_MARKER" >&2
        exit 2
      fi
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
        guard_log dispatch "$TYPE" block "dispatch checkpoint $THIS_DISPATCH_NUMBER"
        printf 'agent-team dispatch guard: this is dispatch #%s — a checkpoint (every %s). Re-triage before continuing: include the exact prompt line "WORKFORCE_BUDGET_ACK: %s dispatches — continuing because <tier and why proportionate>" to proceed.\n' "$THIS_DISPATCH_NUMBER" "$DISPATCH_CHECKPOINT" "$THIS_DISPATCH_NUMBER" >&2
        exit 2
        ;;
    esac
  fi
fi

exit 0
