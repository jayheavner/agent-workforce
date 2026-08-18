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
# The unit of isolation is the CHANGE, not the agent: a dispatch declares one, and this
# guard claims it in the work register and builds or adopts its worktree
# (policy:workspace-isolation). Two live writers in one change are decided by the
# register's writer slot — a durable file — never by re-reading the transcript, which is
# what the retired collision scan did. MUTATING_ROLES in the closeout hook serves
# baseline-capture logic and is a different set — do not conflate the two.
readonly CHANGE_MARKER_PREFIX="CHANGE:"
readonly PARALLEL_SAFE_MARKER="PARALLEL_SAFE: this dispatch writes nothing"
# Roles that MUST declare a change: everything that writes. The debugger and ops MAY
# declare one and it is honoured when present — a diagnosis that will commit claims its
# change like anything else — because their Bash rule refuses git mutation outside a
# claimed tree.
readonly CHANGE_REQUIRED_ROLES="builder test-author executor deployer"
# The two retired declarations, kept only so they can be REFUSED by name.
readonly RETIRED_WORKTREE_PREFIX="WORKTREE:"
readonly RETIRED_PARALLEL_SAFE="PARALLEL_SAFE: no git mutation in this dispatch"
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
# The rule for which paths a lane covers is shared with the lane guard that
# enforces it, so a path outside every lane there cannot be owned by a role here.
# shellcheck source=/dev/null
[ -r "$(dirname "$0")/agent-team-lane-paths.sh" ] && . "$(dirname "$0")/agent-team-lane-paths.sh"
# The workspace half of this guard — claiming a change in the work register and building
# or adopting its worktree — is one file over, so both stay inside the project's
# file-size discipline. A missing library is a broken install and is refused at the call
# site, never silently skipped.
# shellcheck source=hooks/agent-team-dispatch-change.sh
[ -r "$(dirname "$0")/agent-team-dispatch-change.sh" ] \
  && . "$(dirname "$0")/agent-team-dispatch-change.sh"

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
lane_owner() { # $1 absolute path, $2 working tree root -> owning role, or empty
  lane_role_owner "$1" "$2" "$LANES_FILE"
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
  # A refused path is measured in the working tree it came from. When the payload
  # carries no usable directory, a placeholder stands in so a repo-relative
  # refusal still matches repo-relative lanes; the only thing lost is telling an
  # absolute path inside that unknown tree from one outside it.
  ROOT_FOR_LANES="$ROOT"
  [ -n "$ROOT_FOR_LANES" ] || ROOT_FOR_LANES="/__unknown-working-tree__"
  REFUSED="$(jq -rs --arg m "$REFUSAL_MARKER" '
    [ .[] | .. | strings | select(contains($m))
      | [ splits("\n") ] | map(select(contains($m))) | .[] ]
    | unique | .[]
  ' "$TRANSCRIPT" 2>/dev/null)"
  if [ -n "$REFUSED" ] && ! command -v lane_covers >/dev/null 2>&1; then
    guard_log dispatch "$TYPE" block "lane path rules missing"
    printf 'agent-team dispatch guard: a lane refusal is on the record, and agent-team-lane-paths.sh is missing beside this guard, so which role owns that path cannot be decided — the install is incomplete. Blocking rather than failing open; re-run: bash install.sh\n' >&2
    exit 2
  fi
  # Absolute form of a path a refusal or an override named. Both are written by
  # hand or by an agent, so either form arrives: a repo-relative path is joined to
  # the working tree, an absolute or ~-anchored one is taken as it stands.
  as_lane_path() { # $1 raw path -> absolute pattern
    lane_pattern "${1%/}" "$ROOT_FOR_LANES"
  }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    refused_path="${line#*"$REFUSAL_MARKER"}"
    refused_path="${refused_path#*|}"
    refused_path="$(printf '%s' "$refused_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[`"'"'"']//g')"
    [ -n "$refused_path" ] || continue
    case "$PROMPT" in *"$refused_path"*) ;; *) continue ;; esac
    refused_abs="$(as_lane_path "$refused_path")"
    released=0
    # A release covers the path it names AND everything under it. The human is
    # reading a refusal that names one file and releasing the directory the work
    # belongs in; exact string equality made that natural line silently do
    # nothing, which is the escape hatch failing in the one place it is used.
    while IFS= read -r allowed; do
      [ -n "$allowed" ] || continue
      if [ "$allowed" = "$refused_path" ] || lane_covers "$refused_abs" "$(as_lane_path "$allowed")"; then
        released=1
        break
      fi
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
    owner="$(lane_owner "$refused_abs" "$ROOT_FOR_LANES")"
    if [ -z "$owner" ]; then
      # No lane claims it. Inside the working tree that means source or tests,
      # which are the builder's. Outside it, it means no role can write the path
      # at all — and naming the builder there is what closed the loop on
      # 2026-08-04: the one role confined to a git worktree, sent a path that is
      # in nobody's worktree, refused again by a third guard with no exit left.
      if lane_covers "$refused_abs" "$ROOT_FOR_LANES"; then
        owner="builder"
      else
        printf 'agent-team dispatch guard: %s was already refused as out of lane, and it lies outside this project'"'"'s working tree (%s), where no role'"'"'s lane reaches it. Re-routing cannot fix that — every other specialist refuses it for the same reason, and the builder is confined to its own worktree. Two real repairs: put the work in a path a role already owns, or add that directory to the lane configuration (role_lanes in the project'"'"'s .workforce/project.json, or hooks/agent-team-lanes.json in the workforce repo) so it belongs to a role.\nIf you believe the refusal itself was wrong, say so and stop — only your human can release a path, by writing this line in their own message:\n  %s | <path>\nA directory releases everything under it. Do not write that line yourself; a line authored by you is not read as an override.\n' \
          "$refused_path" "$ROOT_FOR_LANES" "$OVERRIDE_MARKER" >&2
        guard_log dispatch "$TYPE" block "refused $refused_path is in no role's lane"
        exit 2
      fi
    fi
    if [ "$TYPE" != "$owner" ]; then
      printf 'agent-team dispatch guard: %s was already refused as out of lane by another specialist, and this dispatch routes it to the %s. A lane refusal is a routing correction, never permission to widen: %s belongs to the %s. Re-dispatch it there, or drop that path from this dispatch if the work genuinely differs.\nIf you believe the refusal itself was wrong, say so and stop — only your human can release a path, by writing this line in their own message:\n  %s | <path>\nA directory releases everything under it. Do not write that line yourself; a line authored by you is not read as an override.\n' \
        "$refused_path" "$TYPE" "$rel" "$owner" "$OVERRIDE_MARKER" >&2
      guard_log dispatch "$TYPE" block "reroute of refused $rel"
      exit 2
    fi
  done <<EOF
$REFUSED
EOF
fi

# --- workspace isolation: the declaration claims the change, the hook builds it.
# The unit of isolation is the CHANGE, so this guard no longer checks a path somebody
# else was supposed to have created: it claims the change in the work register and then
# creates or adopts its worktree. What replaced the old transcript collision scan is the
# register's writer slot — two live writers in one change are decided by a file on disk,
# never by re-reading conversation history, which is the 2026-08-04 defect where one
# malformed declaration poisoned every later builder. The mechanics are one file over, in
# agent-team-dispatch-change.sh, and they are not optional: without them no dispatch can
# be checked for workspace isolation at all.
if ! command -v dispatch_change_gate >/dev/null 2>&1; then
  guard_log dispatch "$TYPE" block "dispatch change library missing"
  printf 'agent-team dispatch guard: agent-team-dispatch-change.sh is missing beside this guard, so no dispatch can be checked for workspace isolation and no change can be claimed — the install is incomplete. Blocking rather than failing open; re-run: bash install.sh\n' >&2
  exit 2
fi
dispatch_change_gate

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
