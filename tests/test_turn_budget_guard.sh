#!/usr/bin/env bash
# tests/test_turn_budget_guard.sh — agent-team-turn-budget-guard.sh: a soft nudge
# that fires before a hard maxTurns kill, not a security boundary. Every uncertain
# case must allow (exit 0); only a confirmed near-cap dispatch on a mutating,
# non-git-status command blocks.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-turn-budget-guard.sh"
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf 'PASS [%s]\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL [%s]: %s\n' "$1" "$2"; }
brief() { printf '%s' "$1" | tr '\n\t' '  ' | cut -c1-240; }

run_guard() { # $1 role $2 payload
  GOUT="$(printf '%s' "$2" | bash "$GUARD" "$1" 2>&1)"
  GRC=$?
}

allow() { run_guard "$2" "$3"; [ "$GRC" -eq 0 ] && pass "$1" || fail "$1" "expected allow, got exit $GRC: $(brief "$GOUT")"; }
block() { run_guard "$2" "$3"; [ "$GRC" -eq 2 ] && pass "$1" || fail "$1" "expected block, got exit $GRC: $(brief "$GOUT")"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/turn-budget-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

# A transcript with N assistant-typed lines, cheaply, matching the guard's own
# fast (non-deduped) count.
make_transcript() { # $1 count -> path
  local n="$1" path
  path="$(mktemp "$WORK/tr.XXXXXX")"
  : > "$path"
  local i=1
  while [ "$i" -le "$n" ]; do
    printf '{"type":"assistant","message":{"id":"msg_%s"}}\n' "$i" >> "$path"
    i=$((i + 1))
  done
  printf '%s' "$path"
}

bash_payload() { # $1 command $2 transcript
  jq -cn --arg c "$1" --arg tr "$2" --arg cwd "$WORK" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,transcript_path:$tr,tool_input:{command:$c}}'
}

# scribe's real cap is 40 (agents/scribe.md). 85% of 40 is 34.
TR_LOW="$(make_transcript 20)"
TR_AT="$(make_transcript 34)"
TR_OVER="$(make_transcript 39)"

allow "well under the cap allows a normal command" scribe "$(bash_payload 'ls' "$TR_LOW")"
block "at the warn threshold, a mutating command blocks" scribe "$(bash_payload 'printf x > out.txt' "$TR_AT")"
block "past the warn threshold, a mutating command still blocks" scribe "$(bash_payload 'printf x > out.txt' "$TR_OVER")"
allow "past the threshold, git status still allows" scribe "$(bash_payload 'git status' "$TR_OVER")"
allow "past the threshold, git commit still allows" scribe "$(bash_payload 'git commit -am wip' "$TR_OVER")"
allow "past the threshold, git diff still allows" scribe "$(bash_payload 'git diff' "$TR_OVER")"

# Fails open on every uncertain case — never blocks on missing information.
allow "an unknown role allows (no cap to compare against)" nonexistent-role "$(bash_payload 'printf x > out.txt' "$TR_OVER")"
allow "a role with no maxTurns in frontmatter allows" orchestrator "$(bash_payload 'printf x > out.txt' "$TR_OVER")"
run_guard scribe "not valid json"
[ "$GRC" -eq 0 ] && pass "malformed payload allows (fails open)" || fail "malformed payload allows (fails open)" "exit $GRC"
GOUT="$(printf '%s' "$(bash_payload 'printf x > out.txt' "$TR_OVER")" | bash "$GUARD" 2>&1)"; GRC=$?
[ "$GRC" -eq 0 ] && pass "no role argument at all allows" || fail "no role argument at all allows" "exit $GRC"

# The real failure mode this hook must not repeat: a thinking-block line and its
# paired tool-use line share one message id (the real pattern this session found
# inflating a naive line count by roughly 1.5x on a real transcript). The count
# must dedupe by id, matching hooks/cost_report.py's own accounting exactly, or
# this hook fires at roughly half the intended threshold instead of 85%.
TR_SPLIT="$(mktemp "$WORK/split.XXXXXX")"
: > "$TR_SPLIT"
i=1
while [ "$i" -le 30 ]; do
  printf '{"type":"assistant","message":{"id":"msg_%s"}}\n' "$i" >> "$TR_SPLIT"
  printf '{"type":"assistant","message":{"id":"msg_%s"}}\n' "$i" >> "$TR_SPLIT"  # same id, second half of the same reply
  i=$((i + 1))
done
# 30 real turns, 60 raw lines. scribe's cap is 40; 85% of 40 is 34 — above 30 real
# turns, so a correct, deduped count must still allow.
allow "60 raw lines sharing 30 real ids stays under the threshold (not inflated to 60)" \
  scribe "$(bash_payload 'printf x > out.txt' "$TR_SPLIT")"

# The refusal, when it fires, names the count, the cap, and the required repair.
run_guard scribe "$(bash_payload 'printf x > out.txt' "$TR_OVER")"
case "$GOUT" in
  *"39"*"40"*"WORKFORCE_REPORT: scribe | partial"*) pass "the refusal names the count, the cap, and the exact repair line" ;;
  *) fail "the refusal names the count, the cap, and the exact repair line" "$(brief "$GOUT")" ;;
esac

printf 'passed=%d failed=%d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
