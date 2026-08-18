#!/usr/bin/env bash
# tests/lib/dispatch-guard-fixture.sh — the world the dispatch-guard suite runs in,
# and the case runner that reports it.
#
# The suite outgrew one file when the guard stopped checking a declared path and
# started claiming a change in the work register: the cases now need a real git
# project, a register of their own, live and dead holder processes, and the guard's
# telemetry redirected. All of that lives here, with the lane-routing cases in
# tests/lib/dispatch-guard-lane-cases.sh, so tests/test_dispatch_guard.sh stays inside
# the project's file-size discipline and every case still runs from that one file.
#
# Safety contract, and as much the reason this file exists as the sharing is:
# AGENT_TEAM_REGISTER_DIR and AGENT_TEAM_TELEMETRY_DIR are pointed INSIDE this run's
# own temporary directory, so no case can read or write the machine's live register or
# its guard telemetry, and everything is removed on exit.
#
# Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case, then a trailing
# `passed=<n> failed=<n>`.

DG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DG_LIB_DIR/../.." && pwd)"
GUARD="$ROOT/hooks/agent-team-dispatch-guard.sh"
REG="$ROOT/hooks/agent-team-register.sh"

PASSED=0
FAILED=0
RC=0
OUT=""

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-guard.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
BGFILE="$WORK/bgpids"
: > "$BGFILE"
dg_cleanup() {
  local p
  while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$BGFILE"
  rm -rf "$WORK"
}
trap dg_cleanup EXIT INT TERM
note_bg() { printf '%s\n' "$1" >> "$BGFILE"; }

# The register and the telemetry this run may touch: its own, never the machine's.
export AGENT_TEAM_REGISTER_DIR="$WORK/register"
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry"
mkdir -p "$AGENT_TEAM_REGISTER_DIR" "$AGENT_TEAM_TELEMETRY_DIR"
chmod 700 "$AGENT_TEAM_REGISTER_DIR"
GUARD_LOG="$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl"

# --- reporting --------------------------------------------------------------
pass_case() { printf 'PASS [%s]\n' "$1"; PASSED=$((PASSED + 1)); }
fail_case() { printf 'FAIL [%s]: %s\n' "$1" "$(printf '%s' "$2" | tr '\n\t' '  ' | cut -c1-420)"
  FAILED=$((FAILED + 1)); }

run() { # $1 payload — sets RC and OUT
  OUT="$(printf '%s' "$1" | bash "$GUARD" 2>&1)"
  RC=$?
  return 0
}

expect() { # $1 expected rc $2 payload $3 label
  run "$2"
  if [ "$RC" -eq "$1" ]; then
    pass_case "$3"
  else
    fail_case "$3" "expected exit $1; observed exit=$RC out=$OUT"
  fi
}
expect_allow() { expect 0 "$1" "$2"; }
expect_block() { expect 2 "$1" "$2"; }

# A case whose assertions are more than an exit code: a function that prints why it
# failed and exits non-zero, exactly as the register and workspace suites do.
run_case() { # $1 label $2 function [args...]
  local label="$1" fn="$2" why rc
  shift 2
  why="$("$fn" "$@" 2>&1)"
  rc=$?
  [ "$rc" -eq 0 ] && { pass_case "$label"; return 0; }
  fail_case "$label" "$why [case exit=$rc]"
  return 0
}

report_totals() {
  printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ]
}

# --- payloads ---------------------------------------------------------------
agent_json() { jq -cn --arg t "$1" '{tool_name:"Agent",tool_input:{subagent_type:$t}}'; }

agent_json_p() { # $1 subagent_type $2 prompt
  jq -cn --arg t "$1" --arg p "$2" '{tool_name:"Agent",tool_input:{subagent_type:$t,prompt:$p}}'
}

agent_json_with_transcript() { # $1 subagent_type $2 transcript $3 prompt
  jq -cn --arg t "$1" --arg tp "$2" --arg p "$3" \
    '{tool_name:"Agent",transcript_path:$tp,tool_input:{subagent_type:$t,prompt:$p}}'
}

agent_json_cwd() { # $1 subagent_type $2 transcript $3 prompt $4 cwd
  jq -cn --arg t "$1" --arg tp "$2" --arg p "$3" --arg cwd "$4" \
    '{tool_name:"Agent",transcript_path:$tp,cwd:$cwd,tool_input:{subagent_type:$t,prompt:$p}}'
}

# The payload a real dispatch carries once a change is declared: a session id the
# register attributes the claim to, and the project directory the claim is scoped to.
dg_payload() { # $1 role $2 prompt $3 session $4 cwd [$5 transcript]
  jq -cn --arg t "$1" --arg p "$2" --arg sid "$3" --arg cwd "$4" --arg tp "${5:-}" \
    '{tool_name:"Agent",session_id:$sid,cwd:$cwd,transcript_path:$tp,
      tool_input:{subagent_type:$t,prompt:$p}}'
}

# --- projects and claims ----------------------------------------------------
# A real git project with the worktree directory ignored, which is what
# workspace_ensure requires before it creates anything.
dg_project() { # $1 dir [$2 ignore-worktrees: yes|no]
  mkdir -p "$1" || return 1
  git -C "$1" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name "Dispatch Guard Fixture"
  if [ "${2:-yes}" = "yes" ]; then
    printf '.claude/worktrees/\n' > "$1/.gitignore"
  else
    printf 'an-unrelated-pattern\n' > "$1/.gitignore"
  fi
  printf 'base\n' > "$1/file.txt"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -qm "init: fixture project" >/dev/null 2>&1 || return 1
  mkdir -p "$1/.claude/worktrees"
}

# One case's own project, so no two cases can see each other's claims or trees.
dg_fixture() { # $1 name [$2 ignore-worktrees] — sets FX and PROJ
  FX="$WORK/$1"
  PROJ="$FX/proj"
  mkdir -p "$FX" || return 1
  dg_project "$PROJ" "${2:-yes}" || return 1
  PROJ="$(cd "$PROJ" && pwd -P)"
}

card_path() { bash "$REG" card-path "$PROJ" "$1" 2>&1; }

slot_path() { # $1 slug
  local cp
  cp="$(card_path "$1")" || return 1
  printf '%s/writers/%s' "$(dirname "$cp")" "$(basename "$cp")"
}

listed_at() { # $1 worktree path $2 full ref
  git -C "$PROJ" worktree list --porcelain 2>/dev/null \
    | awk -v p="worktree $1" -v r="branch $2" '
        $0 == p {seen=1; next}
        seen && $0 == r {found=1}
        /^$/ {seen=0}
        END {exit found ? 0 : 1}'
}

# A live process that is not this test's session process, for a foreign holder card.
foreign_process() { # prints "<pid>\t<lstart>"
  sleep 300 >/dev/null 2>&1 &
  local p=$!
  note_bg "$p"
  printf '%s\t%s' "$p" "$(ps -p "$p" -o lstart=)"
}

# A timecard written by hand, so a case can plant a holder it did not have to become.
write_card() { # $1 slug $2 session $3 pid $4 pid_start $5 state -> prints the path
  local cp key
  cp="$(card_path "$1")" || return 1
  case "$cp" in /*) ;; *) printf 'card-path printed no path: %s' "$cp"; return 1 ;; esac
  mkdir -p "$(dirname "$cp")" || return 1
  key="$(basename "$(dirname "$cp")")"
  jq -n --arg slug "$1" --arg proj "$PROJ" --arg key "$key" --arg sess "$2" \
    --argjson pid "$3" --arg start "$4" --arg state "$5" \
    --arg wt "$PROJ/.claude/worktrees/$1" --arg ref "refs/heads/change/$1" \
    --arg base "$(git -C "$PROJ" rev-parse HEAD)" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:"main",base_sha:$base,
      state:$state,opened:$opened,heartbeat:$hb,writer:null}' > "$cp" || return 1
  printf '%s' "$cp"
}

wait_for_file() { # $1 path
  local i=0
  while [ "$i" -lt 750 ]; do
    [ -e "$1" ] && return 0
    sleep 0.02
    i=$((i + 1))
  done
  return 1
}
wait_for_death() { # $1 pid
  local i=0
  while [ "$i" -lt 750 ]; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.02
    i=$((i + 1))
  done
  return 1
}

# The last fail-open the guard recorded, so a case can prove a control that stopped
# enforcing said so.
last_fail_open() {
  [ -f "$GUARD_LOG" ] || return 0
  jq -rc 'select(.verdict == "fail-open")' "$GUARD_LOG" 2>/dev/null | tail -n1
}

# The criteria block a builder or test-author dispatch must carry, lint-clean.
CRITERIA_BODY='ACCEPTANCE CRITERIA
- [ ] AC-1 (mechanical): slugify("A  B") returns "a-b". Check: `python3 -c "from slug import slugify; import sys; sys.exit(0 if slugify(chr(65)+chr(32)+chr(66))==chr(97)+chr(45)+chr(98) else 1)" || echo "why: wrong slug"` -> expects exit 0.
- [ ] AC-2 (judgment): error messages are actionable. Judge: reviewer. Bar: a bare stack trace with no next step is a fail.'

change_prompt() { # $1 slug — a dispatch that declares its change
  printf 'Implement it.\nCHANGE: %s\n%s\n' "$1" "$CRITERIA_BODY"
}
