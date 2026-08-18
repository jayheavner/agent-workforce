#!/usr/bin/env bash
# tests/test_register_lifecycle.sh — a timecard's life, UNIT tier: how it is named,
# how long it lives, and what a reap sweeps (plan Task 2).
#
# The other half of the unit tier is tests/test_register.sh, which holds the
# DECISIONS — who may claim a change, who may release it, who may write in it. This
# file holds everything about a card's lifetime that those decisions rest on: that
# the claim outlives the hook process that wrote it, that it dies with its session
# and not before, that a recycled pid or an empty file is never a holder, that two
# projects may name the same slug, that an unknown field survives a rewrite, and that
# crash debris is swept. The suites were split when one file outgrew the project's
# size discipline; both source the same fixture and report the same contract.
#
# Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case, then a
# trailing `passed=<n> failed=<n>`.
set -u

REGISTER_TEST_NAME=register-lifecycle-test
REGISTER_TEST_CONCURRENT_CASES=1
# shellcheck source=tests/lib/register-fixture.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/register-fixture.sh"

# --- how long a card lives --------------------------------------------------

case_claim_survives_hook_process() {
  fixture survives || return 1
  local pp rc holder hrc
  pp="$(claim_from_process_tree survivor sess-survivor)"
  wait_for_file "$FX/out/claim.rc" || { printf 'expected the claim child to finish'; return 1; }
  rc="$(cat "$FX/out/claim.rc")"
  expect_rc 0 "$rc" 'the claim to succeed' "$(head -c 200 "$FX/out/claim.out")" || return 1
  kill -0 "$pp" 2>/dev/null || { printf 'expected the session process still alive'; return 1; }
  bash "$REG" reap "$PROJ" >/dev/null 2>&1
  holder="$(bash "$REG" holder "$PROJ" survivor 2>&1)"; hrc=$?
  kill "$pp" 2>/dev/null
  [ "$hrc" -eq 0 ] && [ -n "$holder" ] \
    || { printf 'expected the claim to outlive its writing shell; observed exit=%s out=%s' \
         "$hrc" "$holder"; return 1; }
  # The recorded process is the long-lived parent, not the shell that wrote it.
  expect_jq "$(card_path survivor)" ".pid == $pp" "pid $pp recorded, not the writing shell"
}

case_reaped_after_session_exit() {
  fixture reaped || return 1
  local pp cp out rc
  pp="$(claim_from_process_tree mortal sess-mortal)"
  wait_for_file "$FX/out/claim.rc" || { printf 'expected a claim from the process tree'; return 1; }
  expect_rc 0 "$(cat "$FX/out/claim.rc")" 'the claim to succeed' \
    "$(head -c 200 "$FX/out/claim.out")" || return 1
  cp="$(card_path mortal)"
  bash "$REG" reap "$PROJ" >/dev/null 2>&1
  expect_there "$cp" 'the card surviving a reap while its session lives' || return 1
  kill "$pp" 2>/dev/null
  wait_for_death "$pp" || { printf 'expected the session process to exit'; return 1; }
  reg reap "$PROJ"
  expect_gone "$cp" 'the card reaped once its session died' || return 1
  case "$out" in
    *"reaped mortal"*) ;;
    *) printf 'expected a "reaped mortal <reason>" line; observed %s' "$out"; return 1 ;;
  esac
  reg holder "$PROJ" mortal
  [ "$rc" -eq 0 ] && { printf 'expected no holder after the reap; observed %s' "$out"; return 1; }
  return 0
}

case_recycled_pid_reaped() {
  fixture recycled || return 1
  local cp out rc
  cp="$(write_card recycled sess-recycled "$$" 'Mon Jan  1 00:00:00 2001' ready)" \
    || { printf 'fixture card: %s' "$cp"; return 1; }
  reg reap "$PROJ"
  expect_gone "$cp" 'a live pid with a stale start time reaped' || return 1
  reg holder "$PROJ" recycled
  [ "$rc" -eq 0 ] && { printf 'expected no holder for a recycled pid'; return 1; }
  return 0
}

case_empty_timecard_reaped() {
  fixture empty || return 1
  local cp out rc cp2
  cp="$(card_path reap-me)"
  mkdir -p "$(dirname "$cp")"
  : > "$cp"
  reg reap "$PROJ"
  expect_gone "$cp" 'an empty card reaped' || return 1
  cp2="$(card_path claim-over)"
  printf 'not json at all\n' > "$cp2"
  reg claim "$PROJ" claim-over sess-empty
  expect_rc 0 "$rc" 'a claim over an unparseable card to succeed' "$out" || return 1
  expect_jq "$cp2" '.slug == "claim-over"' 'a valid card written over it'
}

# --- how a card is named ----------------------------------------------------

case_missing_register_dir_is_error() {
  fixture unusable || return 1
  local out rc
  printf 'a file, so no register root can be created under it\n' > "$FX/blocked"
  export AGENT_TEAM_REGISTER_DIR="$FX/blocked/register"
  reg claim "$PROJ" any-slug sess-unusable
  expect_rc 5 "$rc" 'an unusable register root to be an error, not a holder' "$out" || return 1
  case "$out" in
    *mkdir*) ;;
    *) printf 'expected the error to name its repair (mkdir); observed %s' "$out"; return 1 ;;
  esac
}

case_two_projects_one_slug() {
  local shared="$WORK/shared-register" pa pb ca cb
  mkdir -p "$shared" || return 1
  fixture proj-a own || return 1
  export AGENT_TEAM_REGISTER_DIR="$shared"
  pa="$PROJ"
  must claim "$PROJ" fix-typo sess-a || return 1
  ca="$(card_path fix-typo)"
  fixture proj-b own || return 1
  export AGENT_TEAM_REGISTER_DIR="$shared"
  pb="$PROJ"
  must claim "$PROJ" fix-typo sess-b || return 1
  cb="$(card_path fix-typo)"
  [ "$ca" != "$cb" ] \
    || { printf 'expected one card path per project key; observed both at %s' "$ca"; return 1; }
  jq -e --arg p "$pa" '.project == $p' "$ca" >/dev/null \
    && jq -e --arg p "$pb" '.project == $p' "$cb" >/dev/null \
    || { printf 'expected each card to name its own project; observed %s and %s' \
         "$(jq -r '.project' "$ca")" "$(jq -r '.project' "$cb")"; return 1; }
}

case_malformed_slug_refused() {
  fixture bad-slug || return 1
  local s out rc
  for s in '../escape' 'Bad Slug' '-leading' 'has/slash' 'dot..dot' ''; do
    reg claim "$PROJ" "$s" sess-a
    expect_rc 6 "$rc" "slug \"$s\" to be refused" "$out" || return 1
  done
  reg claim "$PROJ" 'good.slug-1_ok' sess-a
  expect_rc 0 "$rc" 'a legal slug to be accepted' "$out"
}

# --- what a rewrite keeps and what a reap sweeps ----------------------------

case_unknown_field_survives_heartbeat() {
  fixture unknown-field || return 1
  local cp out rc
  must claim "$PROJ" future sess-a || return 1
  cp="$(card_path future)"
  # An old heartbeat and an unknown field, so the refresh is visible without waiting
  # a whole second for the clock to move.
  jq '. + {from_a_newer_guard:"keep me", nested:{a:1}, heartbeat:1}' "$cp" > "$cp.seed" \
    && mv "$cp.seed" "$cp"
  reg heartbeat "$PROJ" future
  expect_rc 0 "$rc" 'the heartbeat to succeed' "$out" || return 1
  expect_jq "$cp" '.from_a_newer_guard == "keep me" and .nested.a == 1' 'unknown fields preserved' \
    || return 1
  expect_jq "$cp" '.heartbeat > 1' 'the heartbeat refreshed past its planted value 1'
}

# A crash between the jq and the mv of a merged rewrite leaves a temp file forever.
# It can never be read as a card, but nothing swept it either, so the register grew
# debris with no owner.
case_reap_sweeps_rewrite_debris() {
  fixture debris || return 1
  local cp dp pid start live_debris dead_debris out rc
  must claim "$PROJ" kept sess-debris || return 1
  cp="$(card_path kept)"
  dp="$(dead_process)" || { printf 'could not build a dead process'; return 1; }
  IFS=$'\t' read -r pid start <<< "$dp"
  dead_debris="$cp.rewrite.$pid"
  live_debris="$cp.rewrite.$$"
  printf '{"half":"written"}\n' > "$dead_debris"
  printf '{"half":"written"}\n' > "$live_debris"
  reg reap "$PROJ"
  expect_gone "$dead_debris" 'the debris of a dead process swept' || return 1
  expect_there "$live_debris" 'the debris of a LIVE process left alone' || return 1
  expect_there "$cp" 'the live card untouched by the sweep'
}

# A stranded take token for the slot's CURRENT state blocks its holder's own release
# — safe, and self-healing one reap later, because the sweep collects the token. What
# was wrong was the message: it named the caller itself as the writer standing in its
# way, which reads as a guard defect rather than as "try again after the next reap".
case_release_blocked_by_token_names_the_token() {
  fixture release-token || return 1
  local lock token out rc
  must claim "$PROJ" tokened sess-token || return 1
  must writer-acquire "$PROJ" tokened 'builder#1' || return 1
  lock="$(slot_path tokened)"
  token="$(take_token_path "$lock" "$(digest16 "$lock")")"
  printf '{"pid":1,"pid_start":"long ago"}\n' > "$token" || return 1
  reg writer-release "$PROJ" tokened 'builder#1'
  expect_rc 3 "$rc" 'the release refused while a take token for these bytes stands' "$out" || return 1
  case "$out" in
    *"builder#1 is still the writer"*) ;;
    *) printf 'expected the refusal to say the slot is STILL the caller%ss, not held against it; observed %s' \
         "'" "$out"; return 1 ;;
  esac
  case "$out" in
    *reap*) ;;
    *) printf 'expected the refusal to name the reap that clears the token; observed %s' "$out"; return 1 ;;
  esac
  expect_there "$lock" 'the slot file kept, since nothing was authorised to take it'
}

run_case 'claim survives the hook process that created it' case_claim_survives_hook_process
run_case 'claim is reaped only after the session process exits' case_reaped_after_session_exit
run_case 'a recycled pid with a different start time is reaped' case_recycled_pid_reaped
run_case 'an empty timecard is reaped, not honoured as a holder' case_empty_timecard_reaped
run_case 'a missing register directory is an error, not a holder' case_missing_register_dir_is_error
run_case 'two projects may hold the same slug at once' case_two_projects_one_slug
run_case 'a malformed slug is refused' case_malformed_slug_refused
run_case 'an unknown field survives a heartbeat' case_unknown_field_survives_heartbeat
run_case 'reap sweeps rewrite debris left by a dead process' case_reap_sweeps_rewrite_debris
run_case 'a release blocked by a stranded take token names the token, not the caller' \
  case_release_blocked_by_token_names_the_token

report_totals
