#!/usr/bin/env bash
# agent-team-turn-budget-guard.sh <role> — a soft nudge, not a security boundary.
#
# WHY THIS EXISTS. A dispatched role carries a hard maxTurns cap (agents/<role>.md
# frontmatter). The harness enforces that cap itself, with no warning and no chance
# for the agent to write a final line — confirmed this session against real
# transcripts: a turn-capped dispatch dies mid tool-call, silently, every time.
# Injecting a live, continuously-updated turn count into a running dispatch is NOT
# available in this harness (checked directly against the hook capability reference:
# visible context injection is confirmed only for SessionStart and UserPromptSubmit,
# neither of which fires repeatedly inside a subagent's own tool-call loop). What IS
# available, and already used successfully elsewhere in this project
# (agent-team-worktree-guard.sh), is a PreToolUse block carrying a written reason.
# This hook is that: once a dispatch's own turn count nears its role's cap, every
# further mutating command is refused with instructions to stop cleanly and write a
# partial WORKFORCE_REPORT now, instead of being killed with nothing said a few turns
# later. Read-only git (status/diff/log) and a commit of already-finished work stay
# allowed, so a dispatch can still close out its last clean state before it runs out.
#
# FAILS OPEN, DELIBERATELY, UNLIKE THE WORKTREE GUARD. That guard enforces a security
# boundary (a role must not mutate what it is not permitted to). This hook enforces
# nothing of the kind — it is advisory defense in depth against a silent kill, and a
# false block here (a misread transcript, a missing config file) would only ever cost
# the one thing this project is trying to stop wasting: turns. So every uncertain case
# here is exit 0, never exit 2.
#
# THE COUNT MATCHES THE HARNESS'S OWN UNIT EXACTLY: one reply, deduplicated by its
# own message id, the same rule hooks/cost_report.py already prices by and the same
# rule this session confirmed, against a real transcript known to have hit its real
# 150-turn cap, returns exactly 150 — not a raw line count, which on that same
# transcript returned 226 (a first version of this hook used that cruder count; it
# would have fired at roughly 56% of the real budget instead of the intended 85%,
# checked and corrected before ever being trusted). jq -s over one transcript costs
# single-digit milliseconds even on a multi-megabyte file, checked directly, and this
# project's own worktree guard already re-scans a whole transcript on every mutating
# call — this hook asks nothing new of the harness.
#
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr shown to the agent).
set -u

ROLE="${1:-}"
[ -n "$ROLE" ] || exit 0

GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$GUARD_DIR/../agents"
CAP_FILE="$AGENTS_DIR/$ROLE.md"
[ -r "$CAP_FILE" ] || exit 0

# Read the frontmatter's maxTurns line only — never a role with no cap at all
# (the orchestrator carries none, and this hook is not wired to it anyway).
CAP="$(grep -m1 '^maxTurns:[[:space:]]*[0-9]' "$CAP_FILE" 2>/dev/null \
  | sed -E 's/^maxTurns:[[:space:]]*([0-9]+).*/\1/')"
case "$CAP" in ''|*[!0-9]*) exit 0 ;; esac
[ "$CAP" -gt 0 ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
PARSED="$(cat | jq -c '.' 2>/dev/null)"
[ -n "$PARSED" ] || exit 0

TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# Default threshold: 85% of the role's cap. Overridable per project, the same
# override shape agent-team-worktree-guard.sh already uses for its own config.
THRESHOLD_PCT=85
PROJECT_ROOT="$(printf '%s' "$PARSED" | jq -r '.cwd // empty' 2>/dev/null)"
if [ -n "$PROJECT_ROOT" ]; then
  OVERRIDE="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$OVERRIDE" ] && [ -f "$OVERRIDE/.workforce/project.json" ]; then
    PCT="$(jq -r '.turn_budget_warn_pct // empty' "$OVERRIDE/.workforce/project.json" 2>/dev/null)"
    case "$PCT" in [0-9]*) THRESHOLD_PCT="$PCT" ;; esac
  fi
fi

COUNT="$(jq -rs '[.[] | select(.type=="assistant") | .message.id // empty] | unique | length' \
  "$TRANSCRIPT" 2>/dev/null)"
case "$COUNT" in ''|*[!0-9]*) exit 0 ;; esac

THRESHOLD=$(( CAP * THRESHOLD_PCT / 100 ))
[ "$COUNT" -ge "$THRESHOLD" ] || exit 0

TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty' 2>/dev/null)"
if [ "$TOOL" = "Bash" ]; then
  CMD="$(printf '%s' "$PARSED" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  case "$CMD" in
    *"git status"*|*"git diff"*|*"git log"*|*"git show"*|*"git add"*|*"git commit"*)
      exit 0 ;;
  esac
fi

printf 'agent-team turn-budget guard: this dispatch has used about %s turns against the %s role'"'"'s %s-turn cap — past %s%%, with no warning after this one. A turn-cap kill happens with no chance to write anything: this is the one chance to avoid it. Stop making further changes now. Commit any clean, already-finished work (git add / git commit stay allowed), then end your final message with WORKFORCE_REPORT: %s | partial, stating plainly what stands and what remains — a deliberate partial report the orchestrator can resume beats being cut off with nothing said.\n' \
  "$COUNT" "$ROLE" "$CAP" "$THRESHOLD_PCT" "$ROLE" >&2
exit 2
