#!/usr/bin/env bash
# tests/lib/register-fixture.sh — the throwaway world every register test runs in,
# and the case runner that reports it.
#
# Two suites test the register and both need the same world: a real git project, a
# register directory of their own, hand-written timecards, and processes that are
# genuinely foreign or genuinely dead. tests/test_register.sh is the UNIT tier — it
# must finish in a couple of seconds — and tests/test_register_races.sh is the RACE
# tier, where cases are deliberately multi-second because they start real processes
# and stagger them. Keeping the world here is what lets the unit suite stay inside
# the project's file-size discipline while the race suite grows.
#
# Safety contract, and the reason this file exists as much as the sharing does:
# AGENT_TEAM_REGISTER_DIR and AGENT_TEAM_TELEMETRY_DIR are pointed INSIDE the run's
# own temporary directory by `fixture`, so no case can read or write the machine's
# live register or telemetry, and everything is removed on exit.
#
# A suite sources this file after setting REGISTER_TEST_NAME, then calls `run_case`
# per case and `report_totals` last. Sourcing defines functions, creates the
# temporary directory, and installs the cleanup trap; it runs no case.

FIXTURE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERE="$FIXTURE_LIB_DIR"
ROOT="$(cd "$FIXTURE_LIB_DIR/../.." && pwd)"
REG="$ROOT/hooks/agent-team-register.sh"
# shellcheck source=tests/lib/concurrency.sh
. "$FIXTURE_LIB_DIR/concurrency.sh"

PASSED=0
FAILED=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/${REGISTER_TEST_NAME:-register-test}.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
BGFILE="$WORK/bgpids"
: > "$BGFILE"
cleanup() {
  local p
  while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$BGFILE"
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM
note_bg() { printf '%s\n' "$1" >> "$BGFILE"; }

# Whether cases run CONCURRENTLY, which the unit tier turns on and the race tier
# leaves off. Every case builds its own fixture directory and its own register root,
# so nothing one case writes is visible to another and running them at once changes
# no verdict — it is simply the difference between a tier that waits on twenty-one
# sequences of forks and one that finishes in a couple of seconds. The race tier
# stays sequential on purpose: its cases start eight real processes each and assert
# what their interleaving produced, and another race running beside them would
# compete for the very cores that interleaving is made of. Reports are printed in
# the order the cases were queued either way, so the output does not depend on which
# case finished first.
REGISTER_TEST_CONCURRENT_CASES="${REGISTER_TEST_CONCURRENT_CASES:-}"
CASE_COUNT=0
CASE_LABELS=()
CASE_PIDS=()

# The case itself: run it, and leave its verdict and its explanation on disk, so the
# answer survives the subshell it was computed in.
case_run_one() { # $1 index $2 function [args...]
  local i="$1" fn="$2" why rc t0 t1
  shift 2
  t0="$(date +%s.%N)"
  why="$("$fn" "$@" 2>&1)"
  rc=$?
  t1="$(date +%s.%N)"
  [ -n "${REGISTER_TEST_TIMING:-}" ] && awk -v a="$t0" -v b="$t1" -v l="${CASE_LABELS[i - 1]}" \
    'BEGIN{printf "  %.2fs %s\n", b-a, l}' >&2
  printf '%s' "$why" > "$WORK/case.$i.why"
  printf '%s' "$rc" > "$WORK/case.$i.rc"
}

case_report_one() { # $1 index
  local rc why label="${CASE_LABELS[$1 - 1]}"
  rc="$(cat "$WORK/case.$1.rc" 2>/dev/null)"
  if [ "$rc" = "0" ]; then
    printf 'PASS [%s]\n' "$label"
    PASSED=$((PASSED + 1))
    return 0
  fi
  why="$(tr '\n\t' '  ' < "$WORK/case.$1.why" 2>/dev/null | cut -c1-420)"
  printf 'FAIL [%s]: %s [case exit=%s]\n' "$label" "$why" "${rc:-none}"
  FAILED=$((FAILED + 1))
}

run_case() { # $1 label, $2 function [args...]
  local fn="$2"
  CASE_LABELS+=("$1")
  CASE_COUNT=$((CASE_COUNT + 1))
  shift 2
  if [ -n "$REGISTER_TEST_CONCURRENT_CASES" ]; then
    case_run_one "$CASE_COUNT" "$fn" "$@" &
    CASE_PIDS+=("$!")
    return 0
  fi
  case_run_one "$CASE_COUNT" "$fn" "$@"
  case_report_one "$CASE_COUNT"
}

report_totals() {
  local p i
  for p in ${CASE_PIDS[@]+"${CASE_PIDS[@]}"}; do wait "$p" 2>/dev/null; done
  if [ -n "$REGISTER_TEST_CONCURRENT_CASES" ]; then
    for ((i = 1; i <= CASE_COUNT; i++)); do case_report_one "$i"; done
  fi
  printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ]
}

# The two assertions almost every case makes, so a case reads as its behaviour
# rather than as a wall of diagnostics. Both print WHAT was expected and WHAT was
# observed, because a failure with neither is a failure nobody can act on.
expect_rc() { # $1 want $2 observed $3 what-was-expected $4 the-command-output
  [ "${2:-}" = "$1" ] && return 0
  printf 'expected %s (exit %s); observed exit=%s out=%s' "$3" "$1" "${2:-none}" "${4:-}"
  return 1
}

expect_jq() { # $1 file $2 filter $3 what-was-expected
  jq -e "$2" "$1" >/dev/null 2>&1 && return 0
  printf 'expected %s; observed %s' "$3" "$(head -c 240 "$1" 2>/dev/null)"
  return 1
}

expect_there() { # $1 path $2 what-was-expected
  [ -f "$1" ] && return 0
  printf 'expected %s at %s; observed no such file' "$2" "$1"
  return 1
}

expect_gone() { # $1 path $2 what-was-expected
  [ -f "$1" ] || return 0
  printf 'expected %s; observed the file still at %s' "$2" "$1"
  return 1
}

# Run the register and keep BOTH halves of its answer, which almost every case
# needs: `$out` is everything it said on either stream, `$rc` its exit status. A
# case declaring `local out rc` gets its own copies — Bash scoping is dynamic, so
# the assignment here lands in the caller's locals.
reg() { # $@ subcommand and arguments
  out="$(bash "$REG" "$@" 2>&1)"
  rc=$?
  return 0
}

# A register step a case needs to SUCCEED before its own assertion means anything —
# the claim under test, the slot a displacement starts from. A failure here is a
# broken setup, not a verdict, so it says which step and what the register answered.
must() { # $@ subcommand and arguments
  local out rc
  reg "$@"
  [ "$rc" -eq 0 ] && return 0
  printf 'the setup step `register %s` failed: exit=%s out=%s' "$*" "$rc" "$out"
  return 1
}

# Sixteen hex of a file's SHA-256, computed here rather than borrowed from the
# register, so a test that plants debris names it the way the design says to.
digest16() { # $1 path
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 < "$1" | awk '{print substr($1, 1, 16)}'
  else
    sha256sum < "$1" | awk '{print substr($1, 1, 16)}'
  fi
}

take_token_path() { # $1 taken-path $2 digest
  printf '%s/.take.%s.%s' "$(dirname "$1")" "$(basename "$1")" "$2"
}

# Both waits poll in hundredths of a second and give up after fifteen: the timeout
# is long because a loaded machine is slow, and the step is short because a unit
# tier that spends its time asleep is a unit tier nobody runs.
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

# A real git project, which every card's identity is derived from.
fixture_git_project() { # $1 dir
  mkdir -p "$1" || return 1
  git -C "$1" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name "Register Fixture"
  printf '.claude/worktrees/\n' > "$1/.gitignore"
  printf 'x\n' > "$1/file.txt"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -qm "init: fixture project" >/dev/null 2>&1 || return 1
  mkdir -p "$1/.claude/worktrees"
}

# The world one case runs in: its own register root, its own output directory, and a
# project. The PROJECT is shared by default and built once for the whole run, because
# a card's identity is (project path, register root, slug) and each case's register
# root is private — two cases sharing one project therefore cannot see each other's
# cards, and twenty avoidable `git init`s were most of what made this tier slow. A
# case that must compare two DIFFERENT projects asks for a private one with any
# second argument.
fixture() { # $1 name [own-project] — sets FX, PROJ, REGDIR and exports the dirs
  FX="$WORK/$1"
  REGDIR="$FX/register"
  mkdir -p "$REGDIR" "$FX/out" || return 1
  chmod 700 "$REGDIR"
  export AGENT_TEAM_REGISTER_DIR="$REGDIR"
  export AGENT_TEAM_TELEMETRY_DIR="$FX/telemetry"
  if [ -n "${2:-}" ]; then
    PROJ="$FX/proj"
    fixture_git_project "$PROJ" || return 1
  else
    PROJ="$WORK/shared-proj"
  fi
  PROJ="$(cd "$PROJ" && pwd -P)"
}

card_path() { bash "$REG" card-path "$PROJ" "$1" 2>&1; }

# The slot file's path for a slug, derived the same way the register derives it.
slot_path() { # $1 slug
  local cp
  cp="$(card_path "$1")" || return 1
  printf '%s/writers/%s' "$(dirname "$cp")" "$(basename "$cp")"
}

# A hand-written timecard, placed wherever `card-path` says the card lives.
write_card() { # $1 slug $2 session $3 pid $4 pid_start $5 state -> prints the path
  local slug="$1" sess="$2" pid="$3" start="$4" state="$5" cp key
  cp="$(card_path "$slug")" || { printf 'card-path failed: %s' "$cp"; return 1; }
  case "$cp" in /*) ;; *) printf 'card-path printed no path: %s' "$cp"; return 1 ;; esac
  mkdir -p "$(dirname "$cp")" || return 1
  key="$(basename "$(dirname "$cp")")"
  jq -n --arg slug "$slug" --arg proj "$PROJ" --arg key "$key" --arg sess "$sess" \
    --argjson pid "$pid" --arg start "$start" \
    --arg wt "$PROJ/.claude/worktrees/$slug" --arg ref "refs/heads/change/$slug" \
    --arg base "$(git -C "$PROJ" rev-parse HEAD)" --arg state "$state" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:"refs/heads/main",
      base_sha:$base,state:$state,opened:$opened,heartbeat:$hb,writer:null}' > "$cp" \
    || return 1
  printf '%s' "$cp"
}

# A live process that is NOT this test's session process, for foreign-holder cards.
# Its streams are redirected away: a background job holding the case's stdout open
# would stall the command substitution run_case reads the case through.
foreign_process() { # prints "<pid>\t<lstart>"
  sleep 300 >/dev/null 2>&1 &
  local p=$!
  note_bg "$p"
  printf '%s\t%s' "$p" "$(ps -p "$p" -o lstart=)"
}

# A pid that is genuinely gone, with the start string it had while it lived: the
# shape of a card whose session process has exited.
dead_process() { # prints "<pid>\t<lstart>"
  sleep 300 >/dev/null 2>&1 &
  local p=$! start
  start="$(ps -p "$p" -o lstart=)"
  kill "$p" 2>/dev/null
  wait_for_death "$p" || return 1
  printf '%s\t%s' "$p" "$start"
}

# The two cards almost every holder case starts from: one owned by a live process
# that is not this one, one owned by a process that is genuinely gone. Both print the
# card path, or the reason it could not be built; a case that needs the process the
# card names reads it back out of the card, which is where the register reads it from.
foreign_card() { # $1 slug $2 session [$3 state]
  local pid start
  IFS=$'\t' read -r pid start <<< "$(foreign_process)"
  write_card "$1" "$2" "$pid" "$start" "${3:-ready}"
}

dead_card() { # $1 slug $2 session [$3 state]
  local dp pid start
  dp="$(dead_process)" || { printf 'could not build a dead process'; return 1; }
  IFS=$'\t' read -r pid start <<< "$dp"
  write_card "$1" "$2" "$pid" "$start" "${3:-ready}"
}

# What register_session_process resolves to for a process started from this test:
# the same answer every claim made here records.
this_session_process() {
  bash -c '. "$1"; register_session_process' _ "$REG" 2>/dev/null
}

# A claim written by a short-lived shell child of a long-lived non-shell parent —
# the real shape of a hook run inside a session.
claim_from_process_tree() { # $1 slug $2 session -> prints the parent pid
  local slug="$1" sess="$2" p
  python3 -c 'import subprocess,sys,time; subprocess.run(sys.argv[1:]); time.sleep(300)' \
    bash -c "bash '$REG' claim '$PROJ' '$slug' '$sess' > '$FX/out/claim.out' 2>&1; printf '%s\n' \$? > '$FX/out/claim.rc'" \
    >/dev/null 2>&1 &
  p=$!
  note_bg "$p"
  printf '%s' "$p"
}

# The shared project is built HERE, once, while nothing else is running: no case
# pays for it, and no two cases can race to create it.
fixture_git_project "$WORK/shared-proj" || {
  printf 'register fixture: the shared git project under %s could not be built, so no case can run\n' \
    "$WORK" >&2
  exit 1
}
