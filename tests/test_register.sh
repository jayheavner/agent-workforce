#!/usr/bin/env bash
# tests/test_register.sh — the work register primitive: one timecard per change,
# exclusive by the filesystem's atomic create, alive for exactly as long as the
# session process that claimed it (plan Task 2).
#
# Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case, then a
# trailing `passed=<n> failed=<n>`.
#
# Safety contract: every case runs inside its own throwaway fixture with
# AGENT_TEAM_REGISTER_DIR and AGENT_TEAM_TELEMETRY_DIR pointed inside it, so no
# case can read or write the machine's live register or telemetry.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REG="$ROOT/hooks/agent-team-register.sh"

PASSED=0
FAILED=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/register-test.XXXXXX")"
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

run_case() { # $1 label, $2 function
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

wait_for_file() { # $1 path
  local i=0
  while [ "$i" -lt 150 ]; do
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

fixture() { # $1 name — sets FX, PROJ, REGDIR and exports the register/telemetry dirs
  FX="$WORK/$1"
  PROJ="$FX/proj"
  REGDIR="$FX/register"
  mkdir -p "$PROJ" "$REGDIR" "$FX/out" || return 1
  chmod 700 "$REGDIR"
  export AGENT_TEAM_REGISTER_DIR="$REGDIR"
  export AGENT_TEAM_TELEMETRY_DIR="$FX/telemetry"
  git -C "$PROJ" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$PROJ" config user.email fixture@example.com
  git -C "$PROJ" config user.name "Register Fixture"
  printf '.claude/worktrees/\n' > "$PROJ/.gitignore"
  printf 'x\n' > "$PROJ/file.txt"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "init: fixture project" >/dev/null 2>&1 || return 1
  PROJ="$(cd "$PROJ" && pwd -P)"
  mkdir -p "$PROJ/.claude/worktrees"
}

card_path() { bash "$REG" card-path "$PROJ" "$1" 2>&1; }

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

# --- cases ------------------------------------------------------------------

case_claim_prints_path() {
  fixture claim-path || { printf 'fixture setup failed'; return 1; }
  local out rc cp
  out="$(bash "$REG" claim "$PROJ" first sess-a 2>&1)"; rc=$?
  cp="$(card_path first)"
  [ "$rc" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ "$out" = "$cp" ] || { printf 'expected the card path %s printed; observed %s' "$cp" "$out"; return 1; }
  [ -f "$cp" ] || { printf 'expected a card on disk at %s; observed none' "$cp"; return 1; }
  jq -e --arg s first --arg sess sess-a \
    '.v == 1 and .slug == $s and .session == $sess and .state == "claiming"' "$cp" >/dev/null \
    || { printf 'expected a v1 claiming card for first/sess-a; observed %s' "$(head -c 200 "$cp")"; return 1; }
  jq -e --arg w "$PROJ/.claude/worktrees/first" \
    '.worktree == $w and .ref == "refs/heads/change/first"' "$cp" >/dev/null \
    || { printf 'expected the derived worktree and ref; observed %s' "$(jq -c '{worktree,ref}' "$cp")"; return 1; }
}

case_foreign_live_session_refused() {
  fixture foreign || { printf 'fixture setup failed'; return 1; }
  local fp pid start cp out rc
  fp="$(foreign_process)"
  IFS=$'\t' read -r pid start <<< "$fp"
  cp="$(write_card taken sess-foreign "$pid" "$start" ready)" \
    || { printf 'fixture card failed: %s' "$cp"; return 1; }
  out="$(bash "$REG" claim "$PROJ" taken sess-mine 2>&1)"; rc=$?
  [ "$rc" -eq 3 ] || { printf 'expected exit 3 against a live foreign holder; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *sess-foreign*) ;;
    *) printf 'expected the holder JSON naming sess-foreign; observed %s' "$out"; return 1 ;;
  esac
  jq -e --arg s sess-foreign '.session == $s' "$cp" >/dev/null \
    || { printf 'expected the holder card untouched; observed %s' "$(head -c 200 "$cp")"; return 1; }
}

case_same_session_idempotent() {
  fixture idempotent || { printf 'fixture setup failed'; return 1; }
  local cp opened1 opened2 rc out
  bash "$REG" claim "$PROJ" mine sess-a >/dev/null 2>&1 \
    || { printf 'expected the first claim to succeed'; return 1; }
  cp="$(card_path mine)"
  opened1="$(jq -r '.opened' "$cp")"
  out="$(bash "$REG" claim "$PROJ" mine sess-a 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0 re-claiming as the same session; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  opened2="$(jq -r '.opened' "$cp")"
  [ "$opened1" = "$opened2" ] \
    || { printf 'expected the existing card kept (opened %s); observed a rewrite to %s' "$opened1" "$opened2"; return 1; }
  # Identity on the claim path is the session id, not the process: another id in
  # the SAME process tree is a different claimant and is refused. Without this,
  # twenty racing claimants in one tree would all be "members" and all win.
  out="$(bash "$REG" claim "$PROJ" mine sess-other 2>&1)"; rc=$?
  [ "$rc" -eq 3 ] \
    || { printf 'expected exit 3 for another session id over a live card; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  # The session-id branch is also what lets a RESUMED session adopt its own claim:
  # same id, new process.
  local fp pid start
  fp="$(foreign_process)"
  IFS=$'\t' read -r pid start <<< "$fp"
  write_card resumable sess-resume "$pid" "$start" claiming >/dev/null || return 1
  out="$(bash "$REG" claim "$PROJ" resumable sess-resume 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] \
    || { printf 'expected exit 0 for a matching session id over a foreign pid; observed exit=%s out=%s' "$rc" "$out"; return 1; }
}

case_claim_survives_hook_process() {
  fixture survives || { printf 'fixture setup failed'; return 1; }
  local pp rc holder hrc
  pp="$(claim_from_process_tree survivor sess-survivor)"
  wait_for_file "$FX/out/claim.rc" \
    || { printf 'expected the claim child to finish; observed nothing: %s' "$(head -c 200 "$FX/out/claim.out" 2>/dev/null)"; return 1; }
  rc="$(cat "$FX/out/claim.rc")"
  [ "$rc" -eq 0 ] || { printf 'expected claim exit 0; observed exit=%s out=%s' "$rc" "$(head -c 200 "$FX/out/claim.out")"; return 1; }
  kill -0 "$pp" 2>/dev/null || { printf 'expected the session process still alive'; return 1; }
  bash "$REG" reap "$PROJ" >/dev/null 2>&1
  holder="$(bash "$REG" holder "$PROJ" survivor 2>&1)"; hrc=$?
  kill "$pp" 2>/dev/null
  [ "$hrc" -eq 0 ] && [ -n "$holder" ] \
    || { printf 'expected the claim to outlive its writing shell; observed holder exit=%s out=%s' "$hrc" "$holder"; return 1; }
  # The recorded process is the long-lived parent, not the shell that wrote it.
  jq -e --argjson p "$pp" '.pid == $p' "$(card_path survivor)" >/dev/null \
    || { printf 'expected pid %s recorded; observed %s' "$pp" "$(jq -c '{pid,pid_start}' "$(card_path survivor)")"; return 1; }
}

case_reaped_after_session_exit() {
  fixture reaped || { printf 'fixture setup failed'; return 1; }
  local pp cp out
  pp="$(claim_from_process_tree mortal sess-mortal)"
  wait_for_file "$FX/out/claim.rc" || { printf 'expected a claim from the process tree'; return 1; }
  [ "$(cat "$FX/out/claim.rc")" -eq 0 ] \
    || { printf 'expected claim exit 0; observed %s out=%s' "$(cat "$FX/out/claim.rc")" "$(head -c 200 "$FX/out/claim.out")"; return 1; }
  cp="$(card_path mortal)"
  bash "$REG" reap "$PROJ" >/dev/null 2>&1
  [ -f "$cp" ] || { printf 'expected the card to survive a reap while its session lives; observed it gone'; return 1; }
  kill "$pp" 2>/dev/null
  wait_for_death "$pp" || { printf 'expected the session process to exit'; return 1; }
  out="$(bash "$REG" reap "$PROJ" 2>&1)"
  [ -f "$cp" ] && { printf 'expected the card reaped once its session died; observed it still at %s (reap said %s)' "$cp" "$out"; return 1; }
  case "$out" in
    *"reaped mortal"*) ;;
    *) printf 'expected a "reaped mortal <reason>" line; observed %s' "$out"; return 1 ;;
  esac
  bash "$REG" holder "$PROJ" mortal >/dev/null 2>&1 \
    && { printf 'expected no holder after the reap'; return 1; }
  return 0
}

case_recycled_pid_reaped() {
  fixture recycled || { printf 'fixture setup failed'; return 1; }
  local cp out
  cp="$(write_card recycled sess-recycled "$$" 'Mon Jan  1 00:00:00 2001' ready)" \
    || { printf 'fixture card failed: %s' "$cp"; return 1; }
  out="$(bash "$REG" reap "$PROJ" 2>&1)"
  [ -f "$cp" ] && { printf 'expected a live pid with a stale start time reaped; observed it still at %s (reap said %s)' "$cp" "$out"; return 1; }
  bash "$REG" holder "$PROJ" recycled >/dev/null 2>&1 \
    && { printf 'expected no holder for a recycled pid'; return 1; }
  return 0
}

case_empty_timecard_reaped() {
  fixture empty || { printf 'fixture setup failed'; return 1; }
  local cp out rc cp2
  cp="$(card_path reap-me)"
  mkdir -p "$(dirname "$cp")"
  : > "$cp"
  out="$(bash "$REG" reap "$PROJ" 2>&1)"
  [ -f "$cp" ] && { printf 'expected an empty card reaped; observed it still at %s (reap said %s)' "$cp" "$out"; return 1; }
  cp2="$(card_path claim-over)"
  printf 'not json at all\n' > "$cp2"
  out="$(bash "$REG" claim "$PROJ" claim-over sess-empty 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0 claiming over an unparseable card; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  jq -e --arg s claim-over '.slug == $s' "$cp2" >/dev/null \
    || { printf 'expected a valid card written over it; observed %s' "$(head -c 200 "$cp2")"; return 1; }
}

case_missing_register_dir_is_error() {
  fixture unusable || { printf 'fixture setup failed'; return 1; }
  printf 'a file, so no register root can be created under it\n' > "$FX/blocked"
  export AGENT_TEAM_REGISTER_DIR="$FX/blocked/register"
  local out rc
  out="$(bash "$REG" claim "$PROJ" any-slug sess-unusable 2>&1)"; rc=$?
  [ "$rc" -eq 5 ] || { printf 'expected exit 5 for an unusable register root; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *mkdir*) ;;
    *) printf 'expected the error to name its repair (mkdir); observed %s' "$out"; return 1 ;;
  esac
}

case_two_projects_one_slug() {
  local shared="$WORK/shared-register"
  mkdir -p "$shared" || return 1
  local pa pb ca cb rc_a rc_b
  fixture proj-a || { printf 'fixture setup failed'; return 1; }
  export AGENT_TEAM_REGISTER_DIR="$shared"
  pa="$PROJ"
  bash "$REG" claim "$PROJ" fix-typo sess-a >/dev/null 2>&1; rc_a=$?
  ca="$(card_path fix-typo)"
  fixture proj-b || { printf 'fixture setup failed'; return 1; }
  export AGENT_TEAM_REGISTER_DIR="$shared"
  pb="$PROJ"
  bash "$REG" claim "$PROJ" fix-typo sess-b >/dev/null 2>&1; rc_b=$?
  cb="$(card_path fix-typo)"
  [ "$rc_a" -eq 0 ] && [ "$rc_b" -eq 0 ] \
    || { printf 'expected both projects to claim fix-typo; observed %s/%s' "$rc_a" "$rc_b"; return 1; }
  [ "$ca" != "$cb" ] || { printf 'expected one card path per project key; observed both at %s' "$ca"; return 1; }
  jq -e --arg p "$pa" '.project == $p' "$ca" >/dev/null \
    && jq -e --arg p "$pb" '.project == $p' "$cb" >/dev/null \
    || { printf 'expected each card to name its own project; observed %s and %s' \
         "$(jq -r '.project' "$ca")" "$(jq -r '.project' "$cb")"; return 1; }
}

case_unknown_field_survives_heartbeat() {
  fixture unknown-field || { printf 'fixture setup failed'; return 1; }
  local cp hb1 out rc
  bash "$REG" claim "$PROJ" future sess-a >/dev/null 2>&1 || { printf 'claim failed'; return 1; }
  cp="$(card_path future)"
  jq '. + {from_a_newer_guard:"keep me", nested:{a:1}}' "$cp" > "$cp.seed" && mv "$cp.seed" "$cp"
  hb1="$(jq -r '.heartbeat' "$cp")"
  sleep 1
  out="$(bash "$REG" heartbeat "$PROJ" future 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected heartbeat exit 0; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  jq -e '.from_a_newer_guard == "keep me" and .nested.a == 1' "$cp" >/dev/null \
    || { printf 'expected unknown fields preserved; observed %s' "$(head -c 240 "$cp")"; return 1; }
  [ "$(jq -r '.heartbeat' "$cp")" != "$hb1" ] \
    || { printf 'expected the heartbeat refreshed from %s; observed it unchanged' "$hb1"; return 1; }
}

case_malformed_slug_refused() {
  fixture bad-slug || { printf 'fixture setup failed'; return 1; }
  local s out rc
  for s in '../escape' 'Bad Slug' '-leading' 'has/slash' 'dot..dot' ''; do
    out="$(bash "$REG" claim "$PROJ" "$s" sess-a 2>&1)"; rc=$?
    [ "$rc" -eq 6 ] || { printf 'expected exit 6 for slug "%s"; observed exit=%s out=%s' "$s" "$rc" "$out"; return 1; }
  done
  out="$(bash "$REG" claim "$PROJ" 'good.slug-1_ok' sess-a 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected a legal slug accepted; observed exit=%s out=%s' "$rc" "$out"; return 1; }
}

case_writer_slot_exclusive() {
  fixture writers || { printf 'fixture setup failed'; return 1; }
  local cp out rc
  bash "$REG" claim "$PROJ" shared sess-w >/dev/null 2>&1 || { printf 'claim failed'; return 1; }
  cp="$(card_path shared)"
  out="$(bash "$REG" writer-acquire "$PROJ" shared 'builder#1' 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected the first slot granted; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  jq -e '.writer.slot == "builder#1" and .writer.session == "sess-w" and (.writer.heartbeat | type) == "number"' "$cp" >/dev/null \
    || { printf 'expected writer={slot,session,heartbeat}; observed %s' "$(jq -c '.writer' "$cp")"; return 1; }
  out="$(bash "$REG" writer-acquire "$PROJ" shared 'builder#2' 2>&1)"; rc=$?
  [ "$rc" -eq 3 ] || { printf 'expected exit 3 for a second live writer; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *'builder#1'*) ;;
    *) printf 'expected the refusal to name builder#1; observed %s' "$out"; return 1 ;;
  esac
  jq -e '.writer.slot == "builder#1"' "$cp" >/dev/null \
    || { printf 'expected builder#1 still recorded; observed %s' "$(jq -c '.writer' "$cp")"; return 1; }
  # The same slot re-acquiring is not a second writer.
  bash "$REG" writer-acquire "$PROJ" shared 'builder#1' >/dev/null 2>&1 \
    || { printf 'expected the holding slot to re-acquire its own slot'; return 1; }
  bash "$REG" writer-release "$PROJ" shared >/dev/null 2>&1 || { printf 'writer-release failed'; return 1; }
  jq -e '.writer == null' "$cp" >/dev/null \
    || { printf 'expected writer null after release; observed %s' "$(jq -c '.writer' "$cp")"; return 1; }
  out="$(bash "$REG" writer-acquire "$PROJ" shared 'builder#2' 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected the freed slot granted to builder#2; observed exit=%s out=%s' "$rc" "$out"; return 1; }
}

case_stale_writer_releasable() {
  fixture stale-writer || { printf 'fixture setup failed'; return 1; }
  local cp out rc stale
  bash "$REG" claim "$PROJ" shared sess-s >/dev/null 2>&1 || { printf 'claim failed'; return 1; }
  cp="$(card_path shared)"
  bash "$REG" writer-acquire "$PROJ" shared 'builder#1' >/dev/null 2>&1 \
    || { printf 'expected the first slot granted'; return 1; }
  stale=$(( $(date +%s) - 100000 ))
  jq --argjson hb "$stale" '.writer.heartbeat = $hb' "$cp" > "$cp.tmp" && mv "$cp.tmp" "$cp"
  out="$(bash "$REG" writer-acquire "$PROJ" shared 'builder#2' 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected a stale slot displaced; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  jq -e '.writer.slot == "builder#2"' "$cp" >/dev/null \
    || { printf 'expected builder#2 recorded after displacement; observed %s' "$(jq -c '.writer' "$cp")"; return 1; }
}

run_case 'claim succeeds and prints the card path' case_claim_prints_path
run_case 'a second claim by a foreign live session exits 3 and names the holder' case_foreign_live_session_refused
run_case 'a second claim by the same session is idempotent' case_same_session_idempotent
run_case 'claim survives the hook process that created it' case_claim_survives_hook_process
run_case 'claim is reaped only after the session process exits' case_reaped_after_session_exit
run_case 'a recycled pid with a different start time is reaped' case_recycled_pid_reaped
run_case 'an empty timecard is reaped, not honoured as a holder' case_empty_timecard_reaped
run_case 'a missing register directory is an error, not a holder' case_missing_register_dir_is_error
run_case 'two projects may hold the same slug at once' case_two_projects_one_slug
run_case 'an unknown field survives a heartbeat' case_unknown_field_survives_heartbeat
run_case 'a malformed slug is refused' case_malformed_slug_refused
run_case 'writer slot is exclusive' case_writer_slot_exclusive
run_case 'a stale writer slot is releasable' case_stale_writer_releasable

printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
