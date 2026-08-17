#!/usr/bin/env bash
# tests/test_register.sh — the work register's DECISIONS, UNIT tier: who holds a
# change, who may release it, who may write in it, and what a reap may take away
# (plan Task 2).
#
# Two sibling suites carry the rest. tests/test_register_lifecycle.sh has a card's
# lifetime — how it is named, how long it lives, what a reap sweeps — and
# tests/test_register_races.sh has the cases that need real contending processes,
# beside tests/test_register_concurrency.sh; a green run of THIS file is not evidence
# about a race. Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case,
# then a trailing `passed=<n> failed=<n>`. The world every case runs in, its
# assertions, and the safety contract that keeps it away from the machine's live
# register are all in tests/lib/register-fixture.sh.
set -u

REGISTER_TEST_NAME=register-test
# Cases are independent — each its own fixture directory and its own register root —
# so they run at once and are reported in the order queued at the foot of this file.
REGISTER_TEST_CONCURRENT_CASES=1
# shellcheck source=tests/lib/register-fixture.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/register-fixture.sh"

# --- claiming ---------------------------------------------------------------

case_claim_prints_path() {
  fixture claim-path || return 1
  local out rc cp
  reg claim "$PROJ" first sess-a
  cp="$(card_path first)"
  expect_rc 0 "$rc" 'the claim to succeed' "$out" || return 1
  [ "$out" = "$cp" ] \
    || { printf 'expected the card path %s printed; observed %s' "$cp" "$out"; return 1; }
  expect_there "$cp" 'a card on disk' || return 1
  expect_jq "$cp" '.v == 1 and .slug == "first" and .session == "sess-a" and .state == "claiming"' \
    'a v1 claiming card for first/sess-a'
}

case_foreign_live_session_refused() {
  fixture foreign || return 1
  local cp out rc
  cp="$(foreign_card taken sess-foreign)" || { printf 'fixture card: %s' "$cp"; return 1; }
  reg claim "$PROJ" taken sess-mine
  expect_rc 3 "$rc" 'a refusal against a live foreign holder' "$out" || return 1
  case "$out" in
    *sess-foreign*) ;;
    *) printf 'expected the holder JSON naming sess-foreign; observed %s' "$out"; return 1 ;;
  esac
  expect_jq "$cp" '.session == "sess-foreign"' 'the holder card untouched'
}

case_same_session_idempotent() {
  fixture idempotent || return 1
  local cp opened1 opened2 rc out
  must claim "$PROJ" mine sess-a || return 1
  cp="$(card_path mine)"
  opened1="$(jq -r '.opened' "$cp")"
  reg claim "$PROJ" mine sess-a
  expect_rc 0 "$rc" 're-claiming as the same session to succeed' "$out" || return 1
  opened2="$(jq -r '.opened' "$cp")"
  [ "$opened1" = "$opened2" ] \
    || { printf 'expected the card kept (opened %s); observed a rewrite to %s' "$opened1" "$opened2"
         return 1; }
  # Identity on the claim path is the session id, not the process: another id in the
  # SAME process tree is a different claimant and is refused. Without this, twenty
  # racing claimants in one tree would all be "members" and all win.
  reg claim "$PROJ" mine sess-other
  expect_rc 3 "$rc" 'another session id over a live card to be refused' "$out" || return 1
  # The session-id branch is also what lets a RESUMED session adopt its own claim:
  # same id, new process.
  foreign_card resumable sess-resume claiming >/dev/null || return 1
  reg claim "$PROJ" resumable sess-resume
  expect_rc 0 "$rc" 'a matching session id over a foreign pid to be adopted' "$out"
}

# --- releasing --------------------------------------------------------------

# Release is the other half of exclusion: if any process can delete any card, then
# release-then-claim is a claim-theft path and the whole register is decorative.
case_foreign_release_refused() {
  fixture foreign-release || return 1
  local cp out rc
  cp="$(foreign_card held sess-foreign)" || { printf 'fixture card: %s' "$cp"; return 1; }
  reg release "$PROJ" held sess-mine
  expect_rc 3 "$rc" 'releasing a live foreign claim to be refused' "$out" || return 1
  expect_there "$cp" 'the foreign card still on disk' || return 1
  case "$out" in
    *sess-foreign*) ;;
    *) printf 'expected the refusal to name the holding session; observed %s' "$out"; return 1 ;;
  esac
}

# With no session id there is nothing to compare against, so membership can only be
# the process test. Defaulting the argument to the CARD's own session id would make
# the comparison a tautology and hand every card to every caller.
case_release_without_session_id() {
  fixture release-no-id || return 1
  local cp out rc
  cp="$(foreign_card held sess-foreign)" || { printf 'fixture card: %s' "$cp"; return 1; }
  reg release "$PROJ" held
  expect_rc 3 "$rc" 'a live foreign claim to be refused with no session id' "$out" || return 1
  expect_there "$cp" 'the foreign card still on disk' || return 1
  # The process arm still works: this session's own claim releases with no id given.
  must claim "$PROJ" ours sess-ours || return 1
  reg release "$PROJ" ours
  expect_rc 0 "$rc" "this process' own claim to release with no id" "$out" || return 1
  expect_gone "$(card_path ours)" 'the released card gone' || return 1
  # A card whose process is dead is releasable by anyone: nothing is being protected.
  cp="$(dead_card abandoned sess-gone)" || { printf 'fixture card: %s' "$cp"; return 1; }
  reg release "$PROJ" abandoned
  expect_rc 0 "$rc" 'a dead claim to be releasable by anyone' "$out" || return 1
  expect_gone "$cp" 'the dead card gone'
}

# A resumed session keeps its id and gets a NEW process. Adopting its own claim has
# to re-anchor liveness onto that new process, or the card still names a process that
# is about to exit — after which any reap frees a slug whose worktree the resumed
# session is still writing in.
case_adoption_reanchors_process() {
  fixture reanchor || return 1
  local cp out rc pid mypid mystart
  cp="$(foreign_card resumed sess-resume)" || { printf 'fixture card: %s' "$cp"; return 1; }
  pid="$(jq -r '.pid' "$cp")"
  reg claim "$PROJ" resumed sess-resume
  expect_rc 0 "$rc" 'a session to adopt its own claim' "$out" || return 1
  IFS=$'\t' read -r mypid mystart <<< "$(this_session_process)"
  [ -n "$mypid" ] || { printf 'could not resolve this session process'; return 1; }
  jq -e --argjson p "$mypid" --arg s "$mystart" '.pid == $p and .pid_start == $s' "$cp" >/dev/null \
    || { printf 'expected the card re-anchored to pid %s (%s); observed %s' \
         "$mypid" "$mystart" "$(jq -c '{pid,pid_start}' "$cp")"; return 1; }
  expect_jq "$cp" ".pid != $pid" "the pre-resume pid $pid replaced" || return 1
  expect_jq "$cp" '.session == "sess-resume"' 'the session id unchanged'
}

# --- the writer slot --------------------------------------------------------

case_writer_slot_exclusive() {
  fixture writers || return 1
  local cp out rc
  must claim "$PROJ" shared sess-w || return 1
  cp="$(card_path shared)"
  reg writer-acquire "$PROJ" shared 'builder#1'
  expect_rc 0 "$rc" 'the first slot granted' "$out" || return 1
  expect_jq "$cp" '.writer.slot == "builder#1" and .writer.session == "sess-w"
     and (.writer.heartbeat | type) == "number"' 'writer={slot,session,heartbeat}' || return 1
  reg writer-acquire "$PROJ" shared 'builder#2'
  expect_rc 3 "$rc" 'a second live writer refused' "$out" || return 1
  case "$out" in
    *'builder#1'*) ;;
    *) printf 'expected the refusal to name builder#1; observed %s' "$out"; return 1 ;;
  esac
  expect_jq "$cp" '.writer.slot == "builder#1"' 'builder#1 still recorded' || return 1
  # The same slot re-acquiring is not a second writer.
  reg writer-acquire "$PROJ" shared 'builder#1'
  expect_rc 0 "$rc" 'the holding slot to re-acquire its own slot' "$out"
}

case_stale_writer_releasable() {
  fixture stale-writer || return 1
  local cp out rc stale
  must claim "$PROJ" shared sess-s || return 1
  must writer-acquire "$PROJ" shared 'builder#1' || return 1
  cp="$(card_path shared)"
  stale=$(( $(date +%s) - 100000 ))
  jq --argjson hb "$stale" '.writer.heartbeat = $hb' "$cp" > "$cp.tmp" && mv "$cp.tmp" "$cp"
  reg writer-acquire "$PROJ" shared 'builder#2'
  expect_rc 0 "$rc" 'a stale slot displaced' "$out" || return 1
  expect_jq "$cp" '.writer.slot == "builder#2"' 'builder#2 recorded after displacement'
}

# Releasing the slot is a REMOVAL of the file that decides occupancy, so it is
# authorised exactly like every other removal: only the slot that holds it may take
# it away, and the release names itself to prove which slot that is.
case_writer_release_by_holder() {
  fixture release-holder || return 1
  local cp lock out rc
  must claim "$PROJ" shared sess-w || return 1
  must writer-acquire "$PROJ" shared 'builder#1' || return 1
  cp="$(card_path shared)"
  lock="$(slot_path shared)"
  reg writer-release "$PROJ" shared 'builder#1'
  expect_rc 0 "$rc" 'the holding slot to release itself' "$out" || return 1
  expect_gone "$lock" 'the slot file gone after its holder released it' || return 1
  expect_jq "$cp" '.writer == null' 'the card mirror nulled after release' || return 1
  reg writer-acquire "$PROJ" shared 'builder#2'
  expect_rc 0 "$rc" 'the freed slot granted to builder#2' "$out"
}

# The defect this closes: a release that took no slot name unlinked the slot file
# unconditionally, so the OTHER subagent of the same session could drop the holder's
# exclusion and a third acquirer would then be granted a slot two processes hold.
case_writer_release_foreign_slot_refused() {
  fixture release-foreign || return 1
  local cp lock out rc
  must claim "$PROJ" shared sess-w || return 1
  must writer-acquire "$PROJ" shared 'builder#a' || return 1
  cp="$(card_path shared)"
  lock="$(slot_path shared)"
  reg writer-release "$PROJ" shared 'builder#b'
  expect_rc 3 "$rc" 'a release naming a different slot to be refused' "$out" || return 1
  expect_there "$lock" 'the slot file builder#b tried to drop' || return 1
  expect_jq "$lock" '.slot == "builder#a"' 'builder#a still recorded in the slot file' || return 1
  expect_jq "$cp" '.writer.slot == "builder#a"' 'the card mirror still naming builder#a' || return 1
  # And the exclusion still holds: the third acquirer is refused, not granted.
  reg writer-acquire "$PROJ" shared 'builder#c'
  expect_rc 3 "$rc" 'a third acquirer refused after a foreign release attempt' "$out" || return 1
  # A release with no slot at all is a caller error, never a teardown.
  reg writer-release "$PROJ" shared
  expect_rc 2 "$rc" 'a release naming no slot to be a usage error' "$out" || return 1
  expect_there "$lock" 'the slot file after a nameless release'
}

# --- reaping ----------------------------------------------------------------

# An abandoned take token is crash debris, not a holder — but recovering from it
# inline would mean judging it dead and then removing it, which is the exact
# check-then-act the take exists to abolish. So the reap that meets one leaves the
# card alone, the debris sweep removes the token, and the next pass takes the card.
case_abandoned_token_reaped_later() {
  fixture abandoned-token || return 1
  local cp token out rc
  cp="$(dead_card stranded sess-gone)" || { printf 'fixture card: %s' "$cp"; return 1; }
  token="$(take_token_path "$cp" "$(digest16 "$cp")")"
  # A token in the shape a taker leaves behind, naming the card's own dead process.
  jq -c '{pid, pid_start}' "$cp" > "$token" || return 1
  reg reap "$PROJ"
  expect_there "$cp" \
    'the card left alone while a take token stands, not removed on a judgment' || return 1
  expect_gone "$token" 'the abandoned token swept as debris' || return 1
  reg reap "$PROJ"
  expect_gone "$cp" 'the card reaped on the pass after its token was swept' || return 1
  case "$out" in
    *"reaped stranded"*) ;;
    *) printf 'expected a "reaped stranded <reason>" line on the later pass; observed %s' "$out"
       return 1 ;;
  esac
}

# A reaped claim takes its own writer slot with it — but only its own. A fresh claim
# whose writer acquired a slot in the microsecond after the dead card was taken owns
# that slot file, and a reap that unlinked it by name would silently strip a live
# writer's exclusion.
case_reap_keeps_new_claim_slot() {
  fixture reap-slot || return 1
  local cp lock cp2 lock2 now out rc
  now="$(date +%s)"
  cp="$(dead_card handover sess-dead)" || { printf 'fixture card: %s' "$cp"; return 1; }
  cp2="$(dead_card together sess-also-dead)" || { printf 'fixture card: %s' "$cp2"; return 1; }
  lock="$(slot_path handover)"
  lock2="$(slot_path together)"
  mkdir -p "$(dirname "$lock")" || return 1
  # handover's slot belongs to the NEW claim's session; together's belongs to the
  # dead one, so exactly one of them may go.
  printf '{"slot":"builder#new","session":"sess-fresh","heartbeat":%s}\n' "$now" > "$lock"
  printf '{"slot":"builder#1","session":"sess-also-dead","heartbeat":%s}\n' "$now" > "$lock2"
  reg reap "$PROJ"
  expect_gone "$cp" 'the dead card handover reaped' || return 1
  expect_there "$lock" "the new claim's slot left alone by the reap" || return 1
  expect_jq "$lock" '.session == "sess-fresh"' 'the new session still recorded in its slot file' \
    || return 1
  expect_gone "$cp2" 'the dead card together reaped' || return 1
  expect_gone "$lock2" "the reaped claim's own slot removed with it"
}

run_case 'claim succeeds and prints the card path' case_claim_prints_path
run_case 'a second claim by a foreign live session exits 3 and names the holder' case_foreign_live_session_refused
run_case 'a second claim by the same session is idempotent' case_same_session_idempotent
run_case 'a foreign session cannot release a live claim' case_foreign_release_refused
run_case 'release with no session id falls back to the process test' case_release_without_session_id
run_case "adopting one's own claim re-anchors the recorded process" case_adoption_reanchors_process
run_case 'writer slot is exclusive' case_writer_slot_exclusive
run_case 'a stale writer slot is releasable' case_stale_writer_releasable
run_case 'writer release by the holding slot succeeds' case_writer_release_by_holder
run_case 'writer release naming a different slot is refused' case_writer_release_foreign_slot_refused
run_case 'a card behind an abandoned token is reaped on a later pass' case_abandoned_token_reaped_later
run_case "reap leaves a new claim's writer slot alone" case_reap_keeps_new_claim_slot

report_totals
