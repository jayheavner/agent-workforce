#!/usr/bin/env bash
# tests/acceptance/test_workspace_isolation.sh — THE BAR for the workspace-isolation
# work register (plans/2026-08-17-workspace-isolation-work-register.md).
#
# Authored by the test-author from the reviewed plan, before any implementation
# exists, and read-only to every builder thereafter (the worktree guard enforces
# that for everything under tests/acceptance/). Every case label printed here is a
# label the plan's three stage lists name verbatim; the task's acceptance criteria
# grep for them, so a renamed or dropped label fails a criterion rather than
# passing by absence.
#
# Output contract: one line per case, `PASS [<label>]` or `FAIL [<label>]: <why>`,
# then a trailing `passed=<n> failed=<n>`. Exit is non-zero when any case failed.
#
# Safety contract, non-negotiable: no case reads, writes, or deletes machine state.
# Every case points AGENT_TEAM_REGISTER_DIR and AGENT_TEAM_TELEMETRY_DIR (and the
# closeout hook's state and cost directories) inside its own throwaway fixture, and
# every git mutation happens in a fixture repository created by `git init` under a
# mktemp directory. Nothing here runs a mutating git command against this checkout
# or against the shared checkout it lives in.
#
# Red-by-construction: hooks/agent-team-register.sh, hooks/agent-team-workspace.sh,
# the register-backed dispatch and worktree guards, the closeout ledger check, and
# the hygiene --register view are all unwritten, so every case fails today.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REG_SH="$ROOT/hooks/agent-team-register.sh"
WS_SH="$ROOT/hooks/agent-team-workspace.sh"
DG="$ROOT/hooks/agent-team-dispatch-guard.sh"
WG="$ROOT/hooks/agent-team-worktree-guard.sh"
CLOSEOUT="$ROOT/hooks/agent_team_closeout.py"
HYGIENE="$ROOT/tools/worktree-hygiene.sh"
INSTALL="$ROOT/install.sh"

PASSED=0
FAILED=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/workspace-isolation-acc.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
BGFILE="$WORK/bgpids"
: > "$BGFILE"

cleanup() {
  local p
  while read -r p; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done < "$BGFILE"
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# --- reporting ---------------------------------------------------------------
# A case function prints nothing and returns 0 when it passes; on failure it
# prints why (expected vs observed) and returns non-zero. run_case is the only
# place a report line is produced, so every case reports exactly once even when
# the code under test is missing entirely and the case dies on a missing file.
run_case() { # $1 label, $2 function, [args...]
  local label="$1" fn="$2" why rc
  shift 2
  why="$("$fn" "$@" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf 'PASS [%s]\n' "$label"
    PASSED=$((PASSED + 1))
  else
    why="$(printf '%s' "$why" | tr '\n\t' '  ' | cut -c1-420)"
    printf 'FAIL [%s]: %s [case exit=%s]\n' "$label" "$why" "$rc"
    FAILED=$((FAILED + 1))
  fi
}

note_bg() { printf '%s\n' "$1" >> "$BGFILE"; }

wait_for_file() { # $1 path, $2 tries (0.1s each)
  local i=0
  while [ "$i" -lt "${2:-150}" ]; do
    [ -e "$1" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_death() { # $1 pid
  local i=0
  while [ "$i" -lt 150 ]; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

# --- fixtures ---------------------------------------------------------------
# One fixture per case: a throwaway git project, a private register directory,
# and a private telemetry directory. Sets FX, PROJ, REGDIR and exports the two
# register/telemetry variables. Called inside a case's own subshell, so nothing
# it exports escapes the case.
fixture() { # $1 name, $2 ignore-worktrees (yes|no, default yes)
  FX="$WORK/$1"
  PROJ="$FX/proj"
  REGDIR="$FX/register"
  mkdir -p "$PROJ" "$REGDIR" "$FX/out" || return 1
  chmod 700 "$REGDIR"
  export AGENT_TEAM_REGISTER_DIR="$REGDIR"
  export AGENT_TEAM_TELEMETRY_DIR="$FX/telemetry"
  git -C "$PROJ" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$PROJ" config user.email fixture@example.com
  git -C "$PROJ" config user.name "Acceptance Fixture"
  if [ "${2:-yes}" = "yes" ]; then
    printf '.claude/worktrees/\n' > "$PROJ/.gitignore"
  else
    printf 'an-unrelated-pattern\n' > "$PROJ/.gitignore"
  fi
  mkdir -p "$PROJ/docs" "$PROJ/plans" "$PROJ/src" "$PROJ/tests/acceptance" "$PROJ/tools"
  printf 'note\n' > "$PROJ/docs/note.md"
  printf 'plan\n' > "$PROJ/plans/p.md"
  printf 'src\n' > "$PROJ/src/keep.txt"
  printf 'suite\n' > "$PROJ/tests/acceptance/test_ac.sh"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "init: fixture project" >/dev/null 2>&1 || return 1
  PROJ="$(cd "$PROJ" && pwd -P)"
  mkdir -p "$PROJ/.claude/worktrees"
  return 0
}

mk_worktree() { # $1 slug -> prints the worktree path
  local wt="$PROJ/.claude/worktrees/$1"
  git -C "$PROJ" worktree add -q "$wt" -b "change/$1" main >/dev/null 2>&1 || return 1
  mkdir -p "$wt/src" "$wt/plans" "$wt/docs"
  printf '%s' "$wt"
}

change_commit() { # $1 worktree — a docs-only commit, so the closeout hook's
  # code-change ledger checks (which classify docs as documentation) stay quiet
  # and the only thing under test is the change disposition.
  printf 'changed by the change\n' > "$1/docs/note.md"
  git -C "$1" add -A >/dev/null 2>&1 || return 1
  git -C "$1" commit -qm "docs: work inside the change" >/dev/null 2>&1
}

ps_start() { ps -p "$1" -o lstart=; } # verbatim, exactly as the plan records it

# The card path comes from the register itself (`card-path`), so this suite never
# re-derives the project-key hash — the one derived name the plan does not fix
# byte-for-byte.
card_path() { # $1 slug
  bash "$REG_SH" card-path "$PROJ" "$1" 2>&1
}

write_card() { # $1 slug $2 session $3 pid $4 pid_start $5 state $6 worktree -> prints card path
  local slug="$1" sess="$2" pid="$3" start="$4" state="$5" wt="$6" cp key base
  cp="$(card_path "$slug")" || { printf 'card-path failed: %s' "$cp"; return 1; }
  case "$cp" in
    /*) ;;
    *) printf 'card-path did not print an absolute path: %s' "$cp"; return 1 ;;
  esac
  mkdir -p "$(dirname "$cp")" || return 1
  key="$(basename "$(dirname "$cp")")"
  base="$(git -C "$PROJ" rev-parse HEAD)"
  jq -n --arg slug "$slug" --arg proj "$PROJ" --arg key "$key" --arg sess "$sess" \
    --argjson pid "$pid" --arg start "$start" --arg wt "$wt" \
    --arg ref "refs/heads/change/$slug" --arg base "$base" --arg state "$state" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:"refs/heads/main",
      base_sha:$base,state:$state,opened:$opened,heartbeat:$hb,writer:null}' > "$cp" || return 1
  printf '%s' "$cp"
}

put_card() { # write_card's arguments; discards the path and forwards any error text
  local out
  out="$(write_card "$@")" || { printf '%s' "$out"; return 1; }
  return 0
}

own_transcript() { # $1 path $2 prompt — a subagent's OWN transcript: zero Agent blocks
  jq -cn --arg p "$2" \
    '{type:"user",message:{role:"user",content:[{type:"text",text:$p}]}}' > "$1"
}

listed_at() { # $1 worktree path $2 ref — true when git lists that path at that ref
  git -C "$PROJ" worktree list --porcelain 2>/dev/null \
    | awk -v p="worktree $1" -v r="branch $2" '
        $0 == p {seen=1; next}
        seen && $0 == r {found=1}
        /^$/ {seen=0}
        END {exit found ? 0 : 1}'
}

# --- guard drivers ----------------------------------------------------------
wg_write() { # $1 file $2 transcript $3 session
  jq -cn --arg f "$1" --arg tr "$2" --arg sid "$3" --arg cwd "$PROJ" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,session_id:$sid,
      transcript_path:$tr,tool_input:{file_path:$f,content:"x"}}'
}
wg_bash() { # $1 command $2 transcript $3 session
  jq -cn --arg c "$1" --arg tr "$2" --arg sid "$3" --arg cwd "$PROJ" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,session_id:$sid,
      transcript_path:$tr,tool_input:{command:$c}}'
}
run_guard() { # $1 role $2 payload [$3 HOME override] -> sets GOUT, GRC
  if [ -n "${3:-}" ]; then
    GOUT="$(printf '%s' "$2" | HOME="$3" bash "$WG" "$1" 2>&1)"
  else
    GOUT="$(printf '%s' "$2" | bash "$WG" "$1" 2>&1)"
  fi
  GRC=$?
  return 0
}

dg_payload() { # $1 role $2 prompt $3 session $4 transcript
  jq -cn --arg r "$1" --arg p "$2" --arg sid "$3" --arg tr "$4" --arg cwd "$PROJ" \
    '{tool_name:"Agent",session_id:$sid,cwd:$cwd,transcript_path:$tr,
      tool_input:{subagent_type:$r,prompt:$p}}'
}
run_dispatch() { # $1 payload -> sets DOUT, DRC
  DOUT="$(printf '%s' "$1" | bash "$DG" 2>&1)"
  DRC=$?
  return 0
}

# --- closeout driver --------------------------------------------------------
co_transcript() { # $1 path $2 final message text
  {
    jq -cn '{type:"assistant",message:{content:[{type:"tool_use",id:"tu_1",
      name:"Agent",input:{subagent_type:"scribe",prompt:"write the note"}}]}}'
    jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",
      tool_use_id:"tu_1",content:[{type:"text",text:"done"}]}]}}'
    jq -cn --arg t "$2" '{type:"assistant",timestamp:"2026-08-17T00:00:00.000Z",
      message:{id:"msg_2",model:"claude-sonnet-5",content:[{type:"text",text:$t}],
      usage:{input_tokens:100,output_tokens:50,cache_creation_input_tokens:0,
      cache_read_input_tokens:0}}}'
  } > "$1"
}
run_closeout() { # $1 transcript $2 session -> sets COUT (stdout), CORC, CO_REASON
  local pay
  pay="$(jq -cn --arg tr "$1" --arg cwd "$PROJ" --arg sid "$2" \
    '{session_id:$sid,transcript_path:$tr,cwd:$cwd}')"
  COUT="$(printf '%s' "$pay" | env \
    AGENT_TEAM_CLOSEOUT_STATE="$FX/closeout-state" \
    AGENT_TEAM_COST_DIR="$FX/cost" \
    AGENT_TEAM_TELEMETRY_DIR="$FX/telemetry" \
    AGENT_TEAM_CLOSEOUT_RETRY_DELAY=0 \
    python3 "$CLOSEOUT" 2>/dev/null)"
  CORC=$?
  CO_REASON="$(printf '%s' "$COUT" | jq -r '.reason // ""' 2>/dev/null || printf '')"
  return 0
}

COST_TAIL='

## Cost report

| Model | Cost |
'

###############################################################################
# Stage 1 — the register primitive
###############################################################################

# Twenty real operating-system processes, all launched before any is waited on:
# the filesystem's exclusive create must elect exactly one winner (exit 0) and
# refuse the other nineteen (exit 3).
case_one_winner() {
  fixture race || { printf 'fixture setup failed'; return 1; }
  local outd="$FX/out" i rc winners=0 refusals=0 others=""
  for i in $(seq 1 20); do
    (
      bash "$REG_SH" claim "$PROJ" "raced" "sess-race-$i" \
        > "$outd/$i.out" 2>&1
      printf '%s\n' "$?" > "$outd/$i.rc"
    ) &
    note_bg "$!"
  done
  wait
  for i in $(seq 1 20); do
    if [ ! -f "$outd/$i.rc" ]; then
      others="$others [$i:no-rc-file]"
      continue
    fi
    rc="$(cat "$outd/$i.rc")"
    case "$rc" in
      0) winners=$((winners + 1)) ;;
      3) refusals=$((refusals + 1)) ;;
      *) others="$others [$i:exit=$rc $(head -c 60 "$outd/$i.out" | tr '\n' ' ')]" ;;
    esac
  done
  if [ "$winners" -eq 1 ] && [ "$refusals" -eq 19 ]; then
    return 0
  fi
  printf 'expected winners=1 refusals=19; observed winners=%s refusals=%s other=%s' \
    "$winners" "$refusals" "${others:-none}"
  return 1
}

# The claim is written by a short-lived shell child of a long-lived non-shell
# parent. When the child exits the claim must still be honoured: liveness follows
# the session's harness process, never the hook process that wrote the card.
case_claim_survives_hook() {
  fixture survives || { printf 'fixture setup failed'; return 1; }
  local pypid rc holder hrc
  python3 -c 'import subprocess,sys,time; subprocess.run(sys.argv[1:]); time.sleep(300)' \
    bash -c "bash '$REG_SH' claim '$PROJ' 'survivor' 'sess-survivor' > '$FX/out/claim.out' 2>&1; printf '%s\n' \$? > '$FX/out/claim.rc'" \
    >/dev/null 2>&1 &
  pypid=$!
  note_bg "$pypid"
  if ! wait_for_file "$FX/out/claim.rc"; then
    printf 'expected the claim child to finish; observed no exit status file (register missing?): %s' \
      "$(head -c 200 "$FX/out/claim.out" 2>/dev/null)"
    kill "$pypid" 2>/dev/null
    return 1
  fi
  rc="$(cat "$FX/out/claim.rc")"
  if [ "$rc" -ne 0 ]; then
    printf 'expected claim exit 0 from the short-lived child; observed exit=%s out=%s' \
      "$rc" "$(head -c 200 "$FX/out/claim.out")"
    kill "$pypid" 2>/dev/null
    return 1
  fi
  # The writing shell is gone; the recorded session process (python3) is alive.
  if ! kill -0 "$pypid" 2>/dev/null; then
    printf 'expected the recorded session process to still be alive; observed it absent'
    return 1
  fi
  bash "$REG_SH" reap "$PROJ" >/dev/null 2>&1
  holder="$(bash "$REG_SH" holder "$PROJ" survivor 2>&1)"
  hrc=$?
  kill "$pypid" 2>/dev/null
  if [ "$hrc" -ne 0 ] || [ -z "$holder" ]; then
    printf 'expected the claim to survive its writer and a reap; observed holder exit=%s out=%s' \
      "$hrc" "$(printf '%s' "$holder" | head -c 200)"
    return 1
  fi
  return 0
}

# Reaping is keyed on the recorded session process: alive means the card stays
# whatever a reap is asked to do; dead means it goes.
case_reaped_after_session_exit() {
  fixture reaped || { printf 'fixture setup failed'; return 1; }
  local pypid cp
  python3 -c 'import subprocess,sys,time; subprocess.run(sys.argv[1:]); time.sleep(300)' \
    bash -c "bash '$REG_SH' claim '$PROJ' 'mortal' 'sess-mortal' > '$FX/out/claim.out' 2>&1; printf '%s\n' \$? > '$FX/out/claim.rc'" \
    >/dev/null 2>&1 &
  pypid=$!
  note_bg "$pypid"
  if ! wait_for_file "$FX/out/claim.rc" || [ "$(cat "$FX/out/claim.rc")" -ne 0 ]; then
    printf 'expected a claim from the process tree; observed exit=%s out=%s' \
      "$(cat "$FX/out/claim.rc" 2>/dev/null || printf 'none')" \
      "$(head -c 200 "$FX/out/claim.out" 2>/dev/null)"
    kill "$pypid" 2>/dev/null
    return 1
  fi
  cp="$(card_path mortal)"
  bash "$REG_SH" reap "$PROJ" >/dev/null 2>&1
  if [ ! -f "$cp" ]; then
    printf 'expected the card to survive a reap while its session process lives; observed it removed at %s' "$cp"
    kill "$pypid" 2>/dev/null
    return 1
  fi
  kill "$pypid" 2>/dev/null
  if ! wait_for_death "$pypid"; then
    printf 'expected the session process to exit; observed it still alive (pid=%s)' "$pypid"
    return 1
  fi
  local out
  out="$(bash "$REG_SH" reap "$PROJ" 2>&1)"
  if [ -f "$cp" ]; then
    printf 'expected the card removed once its session process died; observed it still at %s (reap said: %s)' \
      "$cp" "$(printf '%s' "$out" | head -c 160)"
    return 1
  fi
  case "$out" in
    *"reaped mortal"*) ;;
    *) printf 'expected a "reaped mortal <reason>" line; observed: %s' \
         "$(printf '%s' "$out" | head -c 200)"; return 1 ;;
  esac
  if bash "$REG_SH" holder "$PROJ" mortal >/dev/null 2>&1; then
    printf 'expected no holder after the reap; observed holder exit 0'
    return 1
  fi
  return 0
}

# A pid alone is not liveness: this card names a process that IS running while its
# recorded start time is stale, which is exactly what pid recycling looks like.
case_recycled_pid() {
  fixture recycled || { printf 'fixture setup failed'; return 1; }
  local cp out
  cp="$(write_card recycled sess-recycled "$$" 'Mon Jan  1 00:00:00 2001' ready \
        "$PROJ/.claude/worktrees/recycled")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  out="$(bash "$REG_SH" reap "$PROJ" 2>&1)"
  if [ -f "$cp" ]; then
    printf 'expected the recycled-pid card reaped; observed it still at %s (reap said: %s)' \
      "$cp" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  if bash "$REG_SH" holder "$PROJ" recycled >/dev/null 2>&1; then
    printf 'expected no holder for a recycled pid; observed holder exit 0'
    return 1
  fi
  return 0
}

# An unparseable card is dead, never a holder: it is reaped, and a fresh claim
# over it succeeds.
case_empty_timecard() {
  fixture empty || { printf 'fixture setup failed'; return 1; }
  local cp_a cp_b out rc
  cp_a="$(card_path reap-me)" || { printf 'card-path failed: %s' "$cp_a"; return 1; }
  case "$cp_a" in /*) ;; *) printf 'card-path did not print a path: %s' "$cp_a"; return 1 ;; esac
  mkdir -p "$(dirname "$cp_a")"
  : > "$cp_a"
  out="$(bash "$REG_SH" reap "$PROJ" 2>&1)"
  if [ -f "$cp_a" ]; then
    printf 'expected an empty card reaped; observed it still at %s (reap said: %s)' \
      "$cp_a" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  cp_b="$(card_path claim-over)"
  mkdir -p "$(dirname "$cp_b")"
  : > "$cp_b"
  out="$(bash "$REG_SH" claim "$PROJ" claim-over sess-empty 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 claiming over an empty card; observed exit=%s out=%s' \
      "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  if ! jq -e --arg s claim-over '.slug == $s' "$cp_b" >/dev/null 2>&1; then
    printf 'expected the empty card replaced by a valid timecard for claim-over; observed: %s' \
      "$(head -c 200 "$cp_b" 2>/dev/null)"
    return 1
  fi
  return 0
}

# An unusable register root is an error with a repair, never silence and never a
# holder — a broken register must not read as "someone else holds it".
case_missing_register_dir() {
  fixture unusable || { printf 'fixture setup failed'; return 1; }
  printf 'this is a file, so the register root under it cannot be created\n' > "$FX/blocked"
  export AGENT_TEAM_REGISTER_DIR="$FX/blocked/register"
  local out rc
  out="$(bash "$REG_SH" claim "$PROJ" any-slug sess-unusable 2>&1)"
  rc=$?
  if [ "$rc" -ne 5 ]; then
    printf 'expected exit 5 (register unusable) for register root %s; observed exit=%s out=%s' \
      "$AGENT_TEAM_REGISTER_DIR" "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  case "$out" in
    *mkdir*|*"$FX/blocked/register"*) ;;
    *) printf 'expected the error to name its repair (mkdir on the register root); observed: %s' \
         "$(printf '%s' "$out" | head -c 200)"; return 1 ;;
  esac
  return 0
}

# The register is machine-scoped, so the same slug in two unrelated projects is
# two claims, not a collision.
case_two_projects_one_slug() {
  local shared="$WORK/two-projects/register"
  mkdir -p "$shared" || return 1
  export AGENT_TEAM_REGISTER_DIR="$shared"
  export AGENT_TEAM_TELEMETRY_DIR="$WORK/two-projects/telemetry"
  local proj_a proj_b card_a card_b out_a out_b rc_a rc_b
  fixture two-projects-a || { printf 'fixture setup failed'; return 1; }
  export AGENT_TEAM_REGISTER_DIR="$shared"
  proj_a="$PROJ"
  out_a="$(bash "$REG_SH" claim "$PROJ" fix-typo sess-proj-a 2>&1)"; rc_a=$?
  card_a="$(card_path fix-typo)"
  fixture two-projects-b || { printf 'fixture setup failed'; return 1; }
  export AGENT_TEAM_REGISTER_DIR="$shared"
  proj_b="$PROJ"
  out_b="$(bash "$REG_SH" claim "$PROJ" fix-typo sess-proj-b 2>&1)"; rc_b=$?
  card_b="$(card_path fix-typo)"
  if [ "$rc_a" -ne 0 ] || [ "$rc_b" -ne 0 ]; then
    printf 'expected both projects to claim fix-typo (exit 0/0); observed %s/%s out_a=%s out_b=%s' \
      "$rc_a" "$rc_b" "$(printf '%s' "$out_a" | head -c 120)" "$(printf '%s' "$out_b" | head -c 120)"
    return 1
  fi
  if [ "$card_a" = "$card_b" ]; then
    printf 'expected two distinct card paths, one per project key; observed both at %s' "$card_a"
    return 1
  fi
  if [ ! -f "$card_a" ] || [ ! -f "$card_b" ]; then
    printf 'expected both cards on disk; observed a=%s exists=%s b=%s exists=%s' \
      "$card_a" "$([ -f "$card_a" ] && printf yes || printf no)" \
      "$card_b" "$([ -f "$card_b" ] && printf yes || printf no)"
    return 1
  fi
  if ! jq -e --arg p "$proj_a" '.project == $p' "$card_a" >/dev/null 2>&1 \
    || ! jq -e --arg p "$proj_b" '.project == $p' "$card_b" >/dev/null 2>&1; then
    printf 'expected each card to name its own project root; observed %s and %s' \
      "$(jq -r '.project // "unparseable"' "$card_a" 2>/dev/null)" \
      "$(jq -r '.project // "unparseable"' "$card_b" 2>/dev/null)"
    return 1
  fi
  return 0
}

# The installer's five per-file touchpoints, checked file by file in the shapes
# tests/test_install_touchpoints.sh asserts: manifest, backup, rollback restore,
# fresh-install cleanup, forward copy — plus the syntax check for shell hooks.
case_installer_touchpoints() {
  local missing="" f hook_files
  hook_files="$(sed -n 's/^HOOK_FILES="\(.*\)"$/\1/p' "$INSTALL" 2>/dev/null)"
  [ -n "$hook_files" ] || { printf 'expected HOOK_FILES to be readable from install.sh; observed nothing'; return 1; }
  for f in agent-team-register.sh agent-team-workspace.sh agent-team-register.json; do
    [ -f "$ROOT/hooks/$f" ] || missing="$missing $f:absent-from-hooks"
    printf '%s' " $hook_files " | grep -qF " $f " || missing="$missing $f:not-in-HOOK_FILES"
    grep -qF "cp \"\$REPO/hooks/$f\" \"\$HOOKS_DIR/\"" "$INSTALL" || missing="$missing $f:no-forward-copy"
    grep -qF "[ -f \"\$HOOKS_DIR/$f\" ]" "$INSTALL" || missing="$missing $f:no-backup"
    grep -qF "$f) cp \"\$b\" \"\$HOOKS_DIR/\" ;;" "$INSTALL" || missing="$missing $f:no-rollback-restore"
    grep -qF "rm -f \"\$HOOKS_DIR/$f\"" "$INSTALL" || missing="$missing $f:no-fresh-cleanup"
    case "$f" in
      *.sh) grep -qF "bash -n \"\$REPO/hooks/$f\"" "$INSTALL" || missing="$missing $f:no-syntax-check" ;;
    esac
  done
  if [ -n "$missing" ]; then
    printf 'expected all five installer touchpoints (and the bash -n line) for the new hook files; missing:%s' "$missing"
    return 1
  fi
  return 0
}

###############################################################################
# Stage 2 — administration by declaration
###############################################################################

# A dead session's tree is adopted, not fought over: claim from a killable
# process tree, kill it, reap, then re-claim and find the same tree at the same
# ref.
case_reclaim_adopts_tree() {
  fixture adopt || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" pay="$FX/payload.json" pypid wt
  : > "$tr"
  dg_payload executor "Integrate it.
CHANGE: adopted
" sess-adopt-dead "$tr" > "$pay"
  python3 -c 'import subprocess,sys,time; subprocess.run(sys.argv[1:]); time.sleep(300)' \
    bash -c "bash '$DG' < '$pay' > '$FX/out/dg.out' 2>&1; printf '%s\n' \$? > '$FX/out/dg.rc'" \
    >/dev/null 2>&1 &
  pypid=$!
  note_bg "$pypid"
  if ! wait_for_file "$FX/out/dg.rc" || [ "$(cat "$FX/out/dg.rc")" -ne 0 ]; then
    printf 'expected the first dispatch allowed (exit 0); observed exit=%s out=%s' \
      "$(cat "$FX/out/dg.rc" 2>/dev/null || printf 'none')" \
      "$(head -c 200 "$FX/out/dg.out" 2>/dev/null)"
    kill "$pypid" 2>/dev/null
    return 1
  fi
  wt="$PROJ/.claude/worktrees/adopted"
  if [ ! -d "$wt" ] || ! listed_at "$wt" refs/heads/change/adopted; then
    printf 'expected the guard to create %s at refs/heads/change/adopted; observed dir=%s list=%s' \
      "$wt" "$([ -d "$wt" ] && printf present || printf absent)" \
      "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ' | head -c 200)"
    kill "$pypid" 2>/dev/null
    return 1
  fi
  kill "$pypid" 2>/dev/null
  wait_for_death "$pypid" || { printf 'expected the holding session process to exit; observed it alive'; return 1; }
  bash "$REG_SH" reap "$PROJ" >/dev/null 2>&1
  if [ -f "$(card_path adopted)" ]; then
    printf 'expected the dead session card reaped; observed it still at %s' "$(card_path adopted)"
    return 1
  fi
  dg_payload executor "Integrate it.
CHANGE: adopted
" sess-adopt-live "$tr" > "$pay"
  run_dispatch "$(cat "$pay")"
  if [ "$DRC" -ne 0 ]; then
    printf 'expected the re-claim allowed (exit 0); observed exit=%s out=%s' \
      "$DRC" "$(printf '%s' "$DOUT" | head -c 200)"
    return 1
  fi
  if ! listed_at "$wt" refs/heads/change/adopted; then
    printf 'expected the surviving worktree adopted at the same ref; observed list=%s' \
      "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ' | head -c 200)"
    return 1
  fi
  if [ ! -f "$(card_path adopted)" ]; then
    printf 'expected a fresh card for the re-claim; observed none at %s' "$(card_path adopted)"
    return 1
  fi
  return 0
}

# Window A: the claim is written, the tree cannot be created (the worktree
# directory is not gitignored), so the guard releases the card it just wrote —
# and the same session may retry the same slug once the repair is made.
case_retry_after_tree_failure() {
  fixture retry-tree no || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" cp
  : > "$tr"
  run_dispatch "$(dg_payload executor "Integrate it.
CHANGE: retry-tree
" sess-retry "$tr")"
  if [ "$DRC" -ne 2 ]; then
    printf 'expected exit 2 when .claude/worktrees is not gitignored; observed exit=%s out=%s' \
      "$DRC" "$(printf '%s' "$DOUT" | head -c 200)"
    return 1
  fi
  case "$DOUT" in
    *gitignore*) ;;
    *) printf 'expected the refusal to name the .gitignore line to add; observed: %s' \
         "$(printf '%s' "$DOUT" | head -c 200)"; return 1 ;;
  esac
  cp="$(card_path retry-tree)"
  if [ -f "$cp" ]; then
    printf 'expected the failed claim released (no card behind a live pid); observed a card at %s' "$cp"
    return 1
  fi
  printf '.claude/worktrees/\n' >> "$PROJ/.gitignore"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "chore: ignore the worktree directory" >/dev/null 2>&1
  run_dispatch "$(dg_payload executor "Integrate it.
CHANGE: retry-tree
" sess-retry "$tr")"
  if [ "$DRC" -ne 0 ]; then
    printf 'expected the retry allowed (exit 0); observed exit=%s out=%s' \
      "$DRC" "$(printf '%s' "$DOUT" | head -c 200)"
    return 1
  fi
  if ! listed_at "$PROJ/.claude/worktrees/retry-tree" refs/heads/change/retry-tree; then
    printf 'expected the retry to create the tree at refs/heads/change/retry-tree; observed list=%s' \
      "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ' | head -c 200)"
    return 1
  fi
  return 0
}

# Window B: a card left in state "claiming" by this same session (crash before
# ready) is resumed — the tree is completed and the card reaches "ready" — never
# refused.
case_retry_after_crash_before_ready() {
  fixture resume || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" cp wt="$PROJ/.claude/worktrees/crashed"
  : > "$tr"
  cp="$(write_card crashed sess-resume "$$" "$(ps_start "$$")" claiming "$wt")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  run_dispatch "$(dg_payload executor "Integrate it.
CHANGE: crashed
" sess-resume "$tr")"
  if [ "$DRC" -ne 0 ]; then
    printf 'expected the same session to resume its claiming card (exit 0); observed exit=%s out=%s' \
      "$DRC" "$(printf '%s' "$DOUT" | head -c 200)"
    return 1
  fi
  if ! listed_at "$wt" refs/heads/change/crashed; then
    printf 'expected the resumed dispatch to complete the tree at %s; observed list=%s' \
      "$wt" "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ' | head -c 200)"
    return 1
  fi
  if ! jq -e '.state == "ready"' "$cp" >/dev/null 2>&1; then
    printf 'expected the card state to reach "ready"; observed state=%s' \
      "$(jq -r '.state // "unparseable"' "$cp" 2>/dev/null)"
    return 1
  fi
  return 0
}

# A live foreign holder is a durable fact, and the refusal must hand the reader
# every part of it plus the human's escape.
case_foreign_session_refused() {
  fixture foreign || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" hpid wt cp missing=""
  : > "$tr"
  wt="$(mk_worktree busy)" || { printf 'could not create the fixture worktree'; return 1; }
  sleep 300 &
  hpid=$!
  note_bg "$hpid"
  cp="$(write_card busy sess-foreign-holder "$hpid" "$(ps_start "$hpid")" ready "$wt")" \
    || { printf 'could not build the fixture card: %s' "$cp"; kill "$hpid" 2>/dev/null; return 1; }
  run_dispatch "$(dg_payload executor "Integrate it.
CHANGE: busy
" sess-mine "$tr")"
  kill "$hpid" 2>/dev/null
  if [ "$DRC" -ne 2 ]; then
    printf 'expected exit 2 against a live foreign holder; observed exit=%s out=%s' \
      "$DRC" "$(printf '%s' "$DOUT" | head -c 200)"
    return 1
  fi
  case "$DOUT" in *busy*) ;; *) missing="$missing slug" ;; esac
  case "$DOUT" in *sess-foreign-holder*) ;; *) missing="$missing holding-session" ;; esac
  case "$DOUT" in *"$wt"*) ;; *) missing="$missing worktree-path" ;; esac
  case "$DOUT" in *WORKFORCE_OVERRIDE*) ;; *) missing="$missing override-escape" ;; esac
  if [ -n "$missing" ]; then
    printf 'expected the refusal to name the holder fact and its escapes; missing:%s observed: %s' \
      "$missing" "$(printf '%s' "$DOUT" | head -c 250)"
    return 1
  fi
  return 0
}

# One change, one writer at a time: the second slot is refused and told who holds
# it, and the card still records the first slot.
case_two_writers_refused() {
  fixture writers || { printf 'fixture setup failed'; return 1; }
  local cp out rc
  out="$(bash "$REG_SH" claim "$PROJ" shared sess-writers 2>&1)" \
    || { printf 'expected a claim before acquiring a writer slot; observed: %s' \
         "$(printf '%s' "$out" | head -c 200)"; return 1; }
  cp="$(card_path shared)"
  out="$(bash "$REG_SH" writer-acquire "$PROJ" shared 'builder#1' 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected the first writer slot granted (exit 0); observed exit=%s out=%s' \
      "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  out="$(bash "$REG_SH" writer-acquire "$PROJ" shared 'builder#2' 2>&1)"
  rc=$?
  if [ "$rc" -ne 3 ]; then
    printf 'expected exit 3 for a second live writer; observed exit=%s out=%s' \
      "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  case "$out" in
    *'builder#1'*) ;;
    *) printf 'expected the refusal to name the holding slot builder#1; observed: %s' \
         "$(printf '%s' "$out" | head -c 200)"; return 1 ;;
  esac
  if ! jq -e '.writer.slot == "builder#1"' "$cp" >/dev/null 2>&1; then
    printf 'expected the card to still record builder#1 as writer; observed writer=%s' \
      "$(jq -c '.writer // "unparseable"' "$cp" 2>/dev/null)"
    return 1
  fi
  return 0
}

# A writer that died without releasing must not hold the slug forever: past the
# TTL the slot is displaced.
case_stale_writer_releasable() {
  fixture stale-writer || { printf 'fixture setup failed'; return 1; }
  local cp out rc stale
  out="$(bash "$REG_SH" claim "$PROJ" shared sess-stale 2>&1)" \
    || { printf 'expected a claim before acquiring a writer slot; observed: %s' \
         "$(printf '%s' "$out" | head -c 200)"; return 1; }
  cp="$(card_path shared)"
  out="$(bash "$REG_SH" writer-acquire "$PROJ" shared 'builder#1' 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected the first writer slot granted (exit 0); observed exit=%s out=%s' \
      "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  stale=$(( $(date +%s) - 100000 ))
  jq --argjson hb "$stale" '.writer.heartbeat = $hb' "$cp" > "$cp.tmp" 2>/dev/null \
    && mv "$cp.tmp" "$cp" \
    || { printf 'could not age the writer heartbeat; card missing or unparseable at %s' "$cp"; return 1; }
  out="$(bash "$REG_SH" writer-acquire "$PROJ" shared 'builder#2' 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected a stale writer slot displaced (exit 0); observed exit=%s out=%s' \
      "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  if ! jq -e '.writer.slot == "builder#2"' "$cp" >/dev/null 2>&1; then
    printf 'expected the card to record builder#2 after displacement; observed writer=%s' \
      "$(jq -c '.writer // "unparseable"' "$cp" 2>/dev/null)"
    return 1
  fi
  return 0
}

# --- the ten policed roles --------------------------------------------------
# One fixture shared by the ten role cases: a live claim held by this session,
# its real worktree, and a subagent's own dispatch prompt selecting that change.
ROLES_RC=1
ROLES_PROJ=""
ROLES_REG=""
ROLES_TEL=""
ROLES_WT=""
ROLES_TR=""
ROLES_SESSION="sess-roles"
setup_roles_fixture() {
  fixture roles || return 1
  ROLES_PROJ="$PROJ"
  ROLES_REG="$REGDIR"
  ROLES_TEL="$FX/telemetry"
  ROLES_TR="$FX/transcript.jsonl"
  ROLES_WT="$(mk_worktree roles-change)" || return 1
  own_transcript "$ROLES_TR" "Do the work.
CHANGE: roles-change
ACCEPTANCE CRITERIA" || return 1
  put_card roles-change "$ROLES_SESSION" "$$" "$(ps_start "$$")" ready "$ROLES_WT" || return 1
  return 0
}

# Every policed role is refused a write to the shared checkout, and the same role
# is allowed the same kind of write inside the change's claimed worktree — so the
# refusal is confinement, not a guard that refuses everyone everything.
case_shared_checkout_refused() { # $1 role
  local role="$1"
  [ "$ROLES_RC" -eq 0 ] || {
    printf 'fixture setup failed (register card-path missing?): %s' \
      "$(tr '\n' ' ' < "$WORK/roles-setup.log" 2>/dev/null | cut -c1-200)"
    return 1
  }
  PROJ="$ROLES_PROJ"
  export AGENT_TEAM_REGISTER_DIR="$ROLES_REG"
  export AGENT_TEAM_TELEMETRY_DIR="$ROLES_TEL"
  run_guard "$role" "$(wg_write "$ROLES_PROJ/docs/note.md" "$ROLES_TR" "$ROLES_SESSION")"
  local out_refuse="$GOUT" rc_refuse="$GRC"
  run_guard "$role" "$(wg_write "$ROLES_WT/src/new.txt" "$ROLES_TR" "$ROLES_SESSION")"
  if [ "$rc_refuse" -ne 2 ]; then
    printf 'expected exit 2 writing %s/docs/note.md in the shared checkout; observed exit=%s out=%s' \
      "$ROLES_PROJ" "$rc_refuse" "$(printf '%s' "$out_refuse" | head -c 200)"
    return 1
  fi
  if [ "$GRC" -ne 0 ]; then
    printf 'expected exit 0 writing inside the claimed worktree %s; observed exit=%s out=%s' \
      "$ROLES_WT" "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  return 0
}

# Decision 7, branch two: a lane this role owns that resolves outside every git
# working tree is legal with no claim at all — and the same role's in-repository
# lane is not, with the one-line repair named.
case_scribe_memory_allowed() {
  fixture scribe-memory || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" home="$FX/home" mem
  own_transcript "$tr" "Record the lesson. No change is declared." || return 1
  mem="$home/.claude/projects/-fixture-project/memory"
  mkdir -p "$mem" || return 1
  run_guard scribe "$(wg_write "$mem/lesson.md" "$tr" sess-scribe)" "$home"
  if [ "$GRC" -ne 0 ]; then
    printf 'expected exit 0 for the scribe agent-memory lane with no claim; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  run_guard scribe "$(wg_write "$PROJ/docs/note.md" "$tr" sess-scribe)" "$home"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 for an in-repository scribe lane with no claim; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  case "$GOUT" in
    *CHANGE:*) ;;
    *) printf 'expected the refusal to name the repair "CHANGE: <slug>"; observed: %s' \
         "$(printf '%s' "$GOUT" | head -c 200)"; return 1 ;;
  esac
  return 0
}

# The plan document lives with the change it plans: the architect's lane is legal
# inside the claimed tree and refused in the shared checkout.
case_architect_plan_allowed() {
  fixture architect-plan || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" wt cp
  wt="$(mk_worktree plan-change)" || { printf 'could not create the fixture worktree'; return 1; }
  own_transcript "$tr" "Write the plan.
CHANGE: plan-change" || return 1
  cp="$(write_card plan-change sess-architect "$$" "$(ps_start "$$")" ready "$wt")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  run_guard architect "$(wg_write "$wt/plans/2026-08-17-plan.md" "$tr" sess-architect)"
  if [ "$GRC" -ne 0 ]; then
    printf 'expected exit 0 for a plan write inside the claimed tree %s; observed exit=%s out=%s' \
      "$wt" "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  run_guard architect "$(wg_write "$PROJ/plans/2026-08-17-plan.md" "$tr" sess-architect)"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 for the same plan write in the shared checkout; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  return 0
}

# The judge roles are not directory-confined — the verifier must run this very
# suite from the shared checkout — while git mutation from there stays refused.
case_verifier_runs_suite() {
  fixture verifier-run || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" wt cp
  wt="$(mk_worktree judged)" || { printf 'could not create the fixture worktree'; return 1; }
  own_transcript "$tr" "Verify it.
CHANGE: judged" || return 1
  cp="$(write_card judged sess-verifier "$$" "$(ps_start "$$")" ready "$wt")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  run_guard verifier "$(wg_bash 'bash tests/acceptance/test_workspace_isolation.sh' "$tr" sess-verifier)"
  if [ "$GRC" -ne 0 ]; then
    printf 'expected exit 0 running the acceptance suite from the shared checkout; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  run_guard verifier "$(wg_bash "git -C $PROJ commit -am wip" "$tr" sess-verifier)"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 for a git-mutating command in the shared checkout; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  return 0
}

case_reviewer_runs_lint() {
  fixture reviewer-run || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" wt cp
  wt="$(mk_worktree reviewed)" || { printf 'could not create the fixture worktree'; return 1; }
  own_transcript "$tr" "Critique the plan.
CHANGE: reviewed" || return 1
  cp="$(write_card reviewed sess-reviewer "$$" "$(ps_start "$$")" ready "$wt")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  run_guard reviewer "$(wg_bash 'python3 tools/lint_acceptance_checks.py plans/p.md' "$tr" sess-reviewer)"
  if [ "$GRC" -ne 0 ]; then
    printf 'expected exit 0 running the plan lint from the shared checkout; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  run_guard reviewer "$(wg_bash "sed -i '' s/note/other/ $PROJ/docs/note.md" "$tr" sess-reviewer)"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 for an in-place file mutation inside a git working tree; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  return 0
}

# Two live claims and nothing to choose between them is a refusal that lists
# every candidate — never a guess at a peer's workspace.
ambiguity_fixture() { # $1 name -> sets PROJ, WT_ALPHA, WT_BETA
  fixture "$1" || return 1
  WT_ALPHA="$(mk_worktree alpha)" || return 1
  WT_BETA="$(mk_worktree beta)" || return 1
  put_card alpha sess-ambiguous "$$" "$(ps_start "$$")" ready "$WT_ALPHA" || return 1
  put_card beta sess-ambiguous "$$" "$(ps_start "$$")" ready "$WT_BETA" || return 1
  return 0
}

case_two_claims_no_selector() {
  WT_ALPHA=""; WT_BETA=""
  ambiguity_fixture ambiguous-none || { printf ' — fixture setup failed (register card-path missing?)'; return 1; }
  local tr="$FX/transcript.jsonl" missing=""
  own_transcript "$tr" "Do the work. This dispatch names no change." || return 1
  run_guard builder "$(wg_write "$WT_ALPHA/src/new.txt" "$tr" sess-ambiguous)"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 with two live claims and no selector; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  case "$GOUT" in *alpha*) ;; *) missing="$missing alpha" ;; esac
  case "$GOUT" in *beta*) ;; *) missing="$missing beta" ;; esac
  if [ -n "$missing" ]; then
    printf 'expected the refusal to name both candidate slugs; missing:%s observed: %s' \
      "$missing" "$(printf '%s' "$GOUT" | head -c 250)"
    return 1
  fi
  return 0
}

case_selector_names_no_claim() {
  WT_ALPHA=""; WT_BETA=""
  ambiguity_fixture ambiguous-bad || { printf ' — fixture setup failed (register card-path missing?)'; return 1; }
  local tr="$FX/transcript.jsonl" missing=""
  own_transcript "$tr" "Do the work.
CHANGE: gamma" || return 1
  run_guard builder "$(wg_write "$WT_ALPHA/src/new.txt" "$tr" sess-ambiguous)"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 when the selector names no live claim; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  case "$GOUT" in *alpha*) ;; *) missing="$missing alpha" ;; esac
  case "$GOUT" in *beta*) ;; *) missing="$missing beta" ;; esac
  if [ -n "$missing" ]; then
    printf 'expected the refusal to list every candidate slug; missing:%s observed: %s' \
      "$missing" "$(printf '%s' "$GOUT" | head -c 250)"
    return 1
  fi
  return 0
}

# The new PARALLEL_SAFE literal asserts the dispatch writes NOTHING, and is
# verified rather than trusted: the identical write is legal without the marker
# and refused with it.
case_parallel_safe_may_not_write() {
  fixture parallel-safe || { printf 'fixture setup failed'; return 1; }
  local tr_plain="$FX/plain.jsonl" tr_safe="$FX/safe.jsonl" wt cp
  wt="$(mk_worktree solo)" || { printf 'could not create the fixture worktree'; return 1; }
  cp="$(write_card solo sess-parallel "$$" "$(ps_start "$$")" ready "$wt")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  own_transcript "$tr_plain" "Do the work.
CHANGE: solo" || return 1
  own_transcript "$tr_safe" "Do the work.
CHANGE: solo
PARALLEL_SAFE: this dispatch writes nothing" || return 1
  run_guard builder "$(wg_write "$wt/src/new.txt" "$tr_plain" sess-parallel)"
  if [ "$GRC" -ne 0 ]; then
    printf 'expected exit 0 for the same write without the marker (control); observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  run_guard builder "$(wg_write "$wt/src/new.txt" "$tr_safe" sess-parallel)"
  if [ "$GRC" -ne 2 ]; then
    printf 'expected exit 2 once the dispatch declared PARALLEL_SAFE; observed exit=%s out=%s' \
      "$GRC" "$(printf '%s' "$GOUT" | head -c 200)"
    return 1
  fi
  return 0
}

###############################################################################
# Stage 3 — closeout and the operator view
###############################################################################

# A fixture whose change worktree carries one un-integrated docs commit, plus a
# live timecard this session is a member of.
closeout_fixture() { # $1 name $2 slug $3 session -> sets CO_WT, CO_CARD
  fixture "$1" || return 1
  CO_WT="$(mk_worktree "$2")" || return 1
  change_commit "$CO_WT" || return 1
  CO_CARD="$(write_card "$2" "$3" "$$" "$(ps_start "$$")" ready "$CO_WT")" \
    || { printf '%s' "$CO_CARD"; return 1; }
  return 0
}

# The Stop hook is a verifier: it may block, and it may not integrate. Nothing
# about the worktree, the ref, the shared checkout's HEAD, or the timecard may
# change because a Stop fired — and the block proves the register was read.
case_bare_stop_integrates_nothing() {
  CO_WT=""; CO_CARD=""
  closeout_fixture bare-stop held sess-bare \
    || { printf ' — fixture setup failed (register card-path missing?)'; return 1; }
  local tr="$FX/transcript.jsonl" before after head_before head_after card_before
  co_transcript "$tr" "Paused here; nothing else to report."
  before="$(git -C "$PROJ" worktree list --porcelain)"
  head_before="$(git -C "$PROJ" rev-parse HEAD)"
  card_before="$(cat "$CO_CARD")"
  run_closeout "$tr" sess-bare
  after="$(git -C "$PROJ" worktree list --porcelain)"
  head_after="$(git -C "$PROJ" rev-parse HEAD)"
  if [ "$before" != "$after" ]; then
    printf 'expected the worktree registration untouched by a Stop; observed before=[%s] after=[%s]' \
      "$(printf '%s' "$before" | tr '\n' ' ')" "$(printf '%s' "$after" | tr '\n' ' ')"
    return 1
  fi
  if [ "$head_before" != "$head_after" ]; then
    printf 'expected the shared checkout HEAD untouched (no merge); observed %s -> %s' \
      "$head_before" "$head_after"
    return 1
  fi
  if [ ! -f "$CO_CARD" ] || [ "$card_before" != "$(cat "$CO_CARD")" ]; then
    printf 'expected the timecard untouched by a Stop; observed %s' \
      "$([ -f "$CO_CARD" ] && printf rewritten || printf deleted)"
    return 1
  fi
  if ! git -C "$PROJ" show-ref --verify --quiet refs/heads/change/held; then
    printf 'expected refs/heads/change/held to survive the Stop; observed it absent'
    return 1
  fi
  case "$CO_REASON" in
    *held*) ;;
    *) printf 'expected the block to name the held claim (proving the register was read); observed reason=%s stdout=%s' \
         "$(printf '%s' "$CO_REASON" | head -c 200)" "$(printf '%s' "$COUT" | head -c 120)"
       return 1 ;;
  esac
  return 0
}

# A completion claim while a change is held must state that change's disposition,
# and the block hands over the exact line to add.
case_no_disposition_blocked() {
  CO_WT=""; CO_CARD=""
  closeout_fixture no-disposition held sess-nodisp \
    || { printf ' — fixture setup failed (register card-path missing?)'; return 1; }
  local tr="$FX/transcript.jsonl" decision
  co_transcript "$tr" "Delivered the work.$COST_TAIL"
  run_closeout "$tr" sess-nodisp
  decision="$(printf '%s' "$COUT" | jq -r '.decision // ""' 2>/dev/null || printf '')"
  if [ "$decision" != "block" ]; then
    printf 'expected decision=block for a completion with a held claim and no disposition; observed decision=%s stdout=%s' \
      "${decision:-none}" "$(printf '%s' "$COUT" | head -c 200)"
    return 1
  fi
  case "$CO_REASON" in
    *"CHANGE-DISPOSITION: held"*) ;;
    *) printf 'expected the block to carry the exact line "CHANGE-DISPOSITION: held | ..."; observed reason=%s' \
         "$(printf '%s' "$CO_REASON" | head -c 250)"; return 1 ;;
  esac
  return 0
}

# "integrated" is verified against git, and the surviving timecard is itself
# counter-evidence; only a merged ref with no card left standing passes.
case_integrated_is_verified() {
  CO_WT=""; CO_CARD=""
  closeout_fixture integrated verify sess-int-a \
    || { printf ' — fixture setup failed (register card-path missing?)'; return 1; }
  local tr="$FX/transcript.jsonl" decision
  co_transcript "$tr" "Delivered.
CHANGE-DISPOSITION: verify | integrated into refs/heads/main$COST_TAIL"
  # (a) claimed integrated, but the ref is not an ancestor of main.
  run_closeout "$tr" sess-int-a
  decision="$(printf '%s' "$COUT" | jq -r '.decision // ""' 2>/dev/null || printf '')"
  if [ "$decision" != "block" ]; then
    printf 'expected a block when refs/heads/change/verify is not an ancestor of main; observed decision=%s reason=%s' \
      "${decision:-none}" "$(printf '%s' "$CO_REASON" | head -c 200)"
    return 1
  fi
  case "$CO_REASON" in
    *verify*) ;;
    *) printf 'expected that block to name the change "verify" whose integration is unverified; observed reason=%s' \
         "$(printf '%s' "$CO_REASON" | head -c 250)"; return 1 ;;
  esac
  # (b) the merge really happened, but the timecard is still there — the claim
  #     was never released, so integration did not run to completion.
  git -C "$PROJ" merge --no-ff --no-edit change/verify >/dev/null 2>&1 \
    || { printf 'fixture merge failed; cannot test the released-card half'; return 1; }
  put_card verify sess-int-b "$$" "$(ps_start "$$")" ready "$CO_WT" \
    || { printf ' — could not refresh the fixture card'; return 1; }
  run_closeout "$tr" sess-int-b
  decision="$(printf '%s' "$COUT" | jq -r '.decision // ""' 2>/dev/null || printf '')"
  if [ "$decision" != "block" ]; then
    printf 'expected a block while the timecard for an "integrated" change still exists; observed decision=%s reason=%s' \
      "${decision:-none}" "$(printf '%s' "$CO_REASON" | head -c 200)"
    return 1
  fi
  case "$CO_REASON" in
    *agent-team-workspace.sh*) ;;
    *) printf 'expected that block to name the command that integrates (agent-team-workspace.sh); observed reason=%s' \
         "$(printf '%s' "$CO_REASON" | head -c 250)"; return 1 ;;
  esac
  # (c) merged AND released: the verified fact passes.
  rm -f "$CO_CARD"
  run_closeout "$tr" sess-int-c
  case "$CO_REASON" in
    *verify*) printf 'expected no disposition block once the change is merged and its card released; observed reason=%s' \
         "$(printf '%s' "$CO_REASON" | head -c 250)"; return 1 ;;
  esac
  return 0
}

# The operator view: who holds what, which trees nobody claims, and the exact
# removal command — all without changing a thing.
case_hygiene_register_view() {
  fixture hygiene || { printf 'fixture setup failed'; return 1; }
  local held orphan cp out rc before after card_before missing=""
  held="$(mk_worktree held)" || { printf 'could not create the held worktree'; return 1; }
  orphan="$(mk_worktree orphan)" || { printf 'could not create the orphan worktree'; return 1; }
  change_commit "$orphan" || { printf 'could not commit inside the orphan worktree'; return 1; }
  cp="$(write_card held sess-hygiene "$$" "$(ps_start "$$")" ready "$held")" \
    || { printf 'could not build the fixture card: %s' "$cp"; return 1; }
  before="$(git -C "$PROJ" worktree list --porcelain)"
  card_before="$(cat "$cp")"
  out="$(bash "$HYGIENE" "$PROJ" --register 2>&1)"
  rc=$?
  after="$(git -C "$PROJ" worktree list --porcelain)"
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 from worktree-hygiene.sh --register; observed exit=%s out=%s' \
      "$rc" "$(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  case "$out" in *sess-hygiene*) ;; *) missing="$missing holding-session" ;; esac
  case "$out" in *held*) ;; *) missing="$missing held-slug" ;; esac
  printf '%s\n' "$out" | grep -q "unclaimed" || missing="$missing unclaimed-marker"
  printf '%s\n' "$out" | grep -F "unclaimed" | grep -qF "$orphan" || missing="$missing unclaimed-path"
  printf '%s\n' "$out" | grep -qF "worktree remove $orphan" || missing="$missing removal-command"
  if [ -n "$missing" ]; then
    printf 'expected the register block to list the held claim and flag the unclaimed tree; missing:%s observed: %s' \
      "$missing" "$(printf '%s' "$out" | tr '\n' ' ' | head -c 250)"
    return 1
  fi
  if [ "$before" != "$after" ] || [ "$card_before" != "$(cat "$cp" 2>/dev/null)" ]; then
    printf 'expected the report to mutate nothing; observed worktree-list or timecard changed'
    return 1
  fi
  return 0
}

###############################################################################
# The run
###############################################################################

setup_roles_fixture > "$WORK/roles-setup.log" 2>&1
ROLES_RC=$?

# Stage 1
run_case 'exactly one of twenty claimants wins'                      case_one_winner
run_case 'claim survives the hook process that created it'           case_claim_survives_hook
run_case 'claim is reaped only after the session process exits'      case_reaped_after_session_exit
run_case 'a recycled pid with a different start time is reaped'      case_recycled_pid
run_case 'an empty timecard is reaped, not honoured as a holder'     case_empty_timecard
run_case 'a missing register directory is an error, not a holder'    case_missing_register_dir
run_case 'two projects may hold the same slug at once'               case_two_projects_one_slug
run_case 'installer touchpoints cover the new hook files'            case_installer_touchpoints

# Stage 2
run_case 're-claim after reap adopts the surviving worktree'         case_reclaim_adopts_tree
run_case 'a retry after a failed tree creation re-claims the same slug' case_retry_after_tree_failure
run_case 'a retry after a crash before ready completes the claim'    case_retry_after_crash_before_ready
run_case 'a second live session is refused and the holder is named'  case_foreign_session_refused
run_case 'two live writers on one change are refused'                case_two_writers_refused
run_case 'a stale writer slot is releasable'                         case_stale_writer_releasable
for role in builder test-author architect scribe executor deployer verifier reviewer debugger ops; do
  run_case "shared-checkout write refused: $role" case_shared_checkout_refused "$role"
done
run_case 'scribe memory write with no claim is allowed'              case_scribe_memory_allowed
run_case 'architect plan write inside the claimed tree is allowed'   case_architect_plan_allowed
run_case 'verifier runs the acceptance suite from the shared checkout' case_verifier_runs_suite
run_case 'reviewer runs the plan lint from the shared checkout'      case_reviewer_runs_lint
run_case 'two live claims with no selector is a refusal naming both' case_two_claims_no_selector
run_case 'a selector naming no live claim is a refusal naming both'  case_selector_names_no_claim
run_case 'a dispatch declaring PARALLEL_SAFE may not write'          case_parallel_safe_may_not_write

# Stage 3
run_case 'a bare Stop with a live claim integrates nothing'          case_bare_stop_integrates_nothing
run_case 'a completion claim with no change disposition is blocked'  case_no_disposition_blocked
run_case 'an integrated claim survives closeout only as a verified fact' case_integrated_is_verified
run_case 'hygiene lists a held claim and flags an unclaimed tree'    case_hygiene_register_view

printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
