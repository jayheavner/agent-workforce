#!/usr/bin/env bash
# tests/test_register_races.sh — the register's contended facts, RACE tier: every
# case here starts REAL operating-system processes and asserts what their interleaving
# produced (plan Task 2).
#
# Why this is its own suite. Exclusion in the register is the filesystem's atomic
# create and the digest-checked take built on it, and a sequential test proves nothing
# about either: it passes just as happily against a check-then-write implementation
# that loses every real race — which is exactly how these defects survived a green
# suite. So the cases below are deliberately multi-second, they run one at a time so
# that nothing competes for the cores their interleaving is made of, and they live
# apart from tests/test_register.sh so that the unit tier stays a couple of seconds
# long. tests/test_register_concurrency.sh is the third member of this family: it
# races the CLAIM path with twenty claimants.
#
# Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case, then a
# trailing `passed=<n> failed=<n>`.
set -u

REGISTER_TEST_NAME=register-race-test
# shellcheck source=tests/lib/register-fixture.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/register-fixture.sh"

SLOW_CLAIMANT="$HERE/slow-claimant.sh"

# The writer slot is a contended fact, so the only honest test is real processes
# contending for it. A sequential test passes against a check-then-write slot that
# grants every racer at once, which is what the guard would hand two builders
# dispatched in parallel in one message.
case_concurrent_writer_acquires() {
  fixture writer-race || { printf 'fixture setup failed'; return 1; }
  local rounds=10 racers=8 r slug od counts won refused other winners cp
  for ((r = 1; r <= rounds; r++)); do
    slug="race$r"
    must claim "$PROJ" "$slug" sess-race || return 1
    od="$FX/out/writer-$r"
    spawn_racers "$racers" "$od" \
      bash -c 'bash "$1" writer-acquire "$2" "$3" "builder#$RACER_INDEX"' _ "$REG" "$PROJ" "$slug" \
      || { printf 'round %s: could not start the racers' "$r"; return 1; }
    counts="$(racer_status_counts "$od" "$racers")"
    IFS=' ' read -r won refused other <<< "$counts"
    [ "$won" -eq 1 ] \
      || { printf 'round %s: expected exactly one writer granted; observed won=%s refused=%s other=%s' \
           "$r" "$won" "$refused" "$other"; return 1; }
    [ "$refused" -eq $((racers - 1)) ] \
      || { printf 'round %s: expected %s refusals; observed refused=%s other=%s' \
           "$r" "$((racers - 1))" "$refused" "$other"; return 1; }
    winners="$(racer_winners "$od" "$racers")"
    cp="$(card_path "$slug")"
    jq -e --arg s "builder#$winners" '.writer.slot == $s' "$cp" >/dev/null \
      || { printf 'round %s: expected the card to record the one winner builder#%s; observed %s' \
           "$r" "$winners" "$(jq -c '.writer' "$cp")"; return 1; }
  done
}

# Reaping is the other contended fact: the card's removal. Six claimants that all
# judge one dead card dead at the same instant must still produce one winner, and
# the winner's fresh card must survive every loser's reap.
case_reap_race_keeps_one_winner() {
  fixture reap-race || { printf 'fixture setup failed'; return 1; }
  local rounds=15 racers=6 r cp od counts won refused other winners sess
  for ((r = 1; r <= rounds; r++)); do
    cp="$(dead_card "dead$r" sess-departed)" \
      || { printf 'round %s: fixture card failed: %s' "$r" "$cp"; return 1; }
    od="$FX/out/reap-$r"
    spawn_racers "$racers" "$od" \
      bash -c 'bash "$1" 0.15 "$2" "$3" "sess-racer-$RACER_INDEX"' _ \
      "$SLOW_CLAIMANT" "$PROJ" "dead$r" \
      || { printf 'round %s: could not start the racers' "$r"; return 1; }
    counts="$(racer_status_counts "$od" "$racers")"
    IFS=' ' read -r won refused other <<< "$counts"
    [ "$won" -eq 1 ] \
      || { printf 'round %s: expected exactly one claimant over the dead card; observed won=%s refused=%s other=%s' \
           "$r" "$won" "$refused" "$other"; return 1; }
    [ -f "$cp" ] \
      || { printf 'round %s: expected the winner card present at %s; observed it destroyed by a loser reap' \
           "$r" "$cp"; return 1; }
    winners="$(racer_winners "$od" "$racers")"
    sess="$(jq -r '.session // empty' "$cp" 2>/dev/null)"
    [ "$sess" = "sess-racer-$winners" ] \
      || { printf 'round %s: expected the card to belong to the one winner sess-racer-%s; observed session=%s' \
           "$r" "$winners" "$sess"; return 1; }
  done
}

# The defect this closes, under real concurrency. `writer-release` used to take no
# slot name and unlink the slot file unconditionally, so any process could drop the
# holder's exclusion — and the moment it was gone, the next acquirer was GRANTED a
# slot the original holder still believed was its own. Three poachers try to release
# a slot they do not hold while three more try to acquire it, all at once, for ten
# rounds: the answer every round is that nobody was granted anything and the original
# holder is still the holder, in the slot file and in the card's mirror alike.
case_foreign_release_never_hands_over() {
  fixture foreign-release-race || { printf 'fixture setup failed'; return 1; }
  local rounds=10 racers=6 r slug lock cp od counts won refused other
  for ((r = 1; r <= rounds; r++)); do
    slug="held$r"
    must claim "$PROJ" "$slug" sess-holder || return 1
    must writer-acquire "$PROJ" "$slug" 'builder#a' || return 1
    lock="$(slot_path "$slug")"
    cp="$(card_path "$slug")"
    od="$FX/out/poach-$r"
    spawn_racers "$racers" "$od" bash -c '
      if [ $((RACER_INDEX % 2)) -eq 0 ]; then
        bash "$1" writer-release "$2" "$3" "builder#poacher$RACER_INDEX"
      else
        bash "$1" writer-acquire "$2" "$3" "builder#poacher$RACER_INDEX"
      fi' _ "$REG" "$PROJ" "$slug" \
      || { printf 'round %s: could not start the racers' "$r"; return 1; }
    counts="$(racer_status_counts "$od" "$racers")"
    IFS=' ' read -r won refused other <<< "$counts"
    [ "$won" -eq 0 ] \
      || { printf 'round %s: expected no poacher to release or acquire the held slot; observed won=%s refused=%s other=%s' \
           "$r" "$won" "$refused" "$other"; return 1; }
    [ "$refused" -eq "$racers" ] \
      || { printf 'round %s: expected all %s poachers refused; observed refused=%s other=%s' \
           "$r" "$racers" "$refused" "$other"; return 1; }
    [ -f "$lock" ] \
      || { printf 'round %s: expected the slot file %s intact; observed a poacher dropped it' \
           "$r" "$lock"; return 1; }
    jq -e '.slot == "builder#a"' "$lock" >/dev/null \
      || { printf 'round %s: expected builder#a still the recorded holder; observed %s' \
           "$r" "$(head -c 200 "$lock")"; return 1; }
    jq -e '.writer.slot == "builder#a"' "$cp" >/dev/null \
      || { printf 'round %s: expected the card mirror still naming builder#a; observed %s' \
           "$r" "$(jq -c '.writer' "$cp")"; return 1; }
  done
}

# The defect this closes, under real concurrency. A take token whose taker was killed
# mid-take is crash debris, and the recovery that used to run inline — judge the taker
# dead, remove the token, create a fresh one — was itself a check-then-act: two racers
# both failed the create, both judged the taker dead, and both ended up holding "the"
# exclusive take for one digest, after which the loser's unlink landed on the winner's
# fresh card. So a standing token now refuses EVERY remover: six slow claimants, each
# holding a "this card is dead" verdict at a different instant, must all be refused
# while it stands. The token is then swept as debris by the reap, and only after that
# does a second wave of six elect exactly one winner — the liveness cost of the fix is
# one reap cycle, and this is where that is asserted rather than assumed.
case_abandoned_token_no_second_remover() {
  fixture token-race || { printf 'fixture setup failed'; return 1; }
  local rounds=5 racers=6 r cp token od counts won refused other winners sess
  for ((r = 1; r <= rounds; r++)); do
    cp="$(dead_card "stranded$r" sess-departed)" \
      || { printf 'round %s: fixture card failed: %s' "$r" "$cp"; return 1; }
    token="$(take_token_path "$cp" "$(digest16 "$cp")")"
    # A token in the shape a killed taker leaves behind: it names the card's own
    # process, which is gone.
    jq -c '{pid, pid_start}' "$cp" > "$token" || return 1
    od="$FX/out/token-$r"
    spawn_racers "$racers" "$od" \
      bash -c 'bash "$1" 0.15 "$2" "$3" "sess-racer-$RACER_INDEX"' _ \
      "$SLOW_CLAIMANT" "$PROJ" "stranded$r" \
      || { printf 'round %s: could not start the racers' "$r"; return 1; }
    counts="$(racer_status_counts "$od" "$racers")"
    IFS=' ' read -r won refused other <<< "$counts"
    [ "$won" -eq 0 ] \
      || { printf 'round %s: expected NO remover behind a standing take token; observed won=%s refused=%s other=%s' \
           "$r" "$won" "$refused" "$other"; return 1; }
    [ -f "$cp" ] \
      || { printf 'round %s: expected the stranded card untouched while its token stands; observed it removed' \
           "$r"; return 1; }
    sess="$(jq -r '.session // empty' "$cp" 2>/dev/null)"
    [ "$sess" = "sess-departed" ] \
      || { printf 'round %s: expected the original dead card still at the path; observed session=%s' \
           "$r" "$sess"; return 1; }
    # The reap sweeps the debris, and only then is the card takeable.
    bash "$REG" reap "$PROJ" >/dev/null 2>&1
    [ -f "$token" ] \
      && { printf 'round %s: expected the abandoned token %s swept by the reap' "$r" "$token"; return 1; }
    od="$FX/out/token-after-$r"
    spawn_racers "$racers" "$od" \
      bash -c 'bash "$1" 0.15 "$2" "$3" "sess-after-$RACER_INDEX"' _ \
      "$SLOW_CLAIMANT" "$PROJ" "stranded$r" \
      || { printf 'round %s: could not start the second wave' "$r"; return 1; }
    counts="$(racer_status_counts "$od" "$racers")"
    IFS=' ' read -r won refused other <<< "$counts"
    [ "$won" -eq 1 ] \
      || { printf 'round %s: expected exactly one winner once the token was swept; observed won=%s refused=%s other=%s' \
           "$r" "$won" "$refused" "$other"; return 1; }
    winners="$(racer_winners "$od" "$racers")"
    sess="$(jq -r '.session // empty' "$cp" 2>/dev/null)"
    [ "$sess" = "sess-after-$winners" ] \
      || { printf 'round %s: expected the card to belong to the one winner sess-after-%s; observed session=%s' \
           "$r" "$winners" "$sess"; return 1; }
  done
}

run_case 'concurrent writer acquires elect exactly one winner' case_concurrent_writer_acquires
run_case 'reaping a dead card never destroys the card that replaced it' case_reap_race_keeps_one_winner
run_case 'a foreign release cannot hand the slot to a third acquirer' case_foreign_release_never_hands_over
run_case 'an abandoned take token yields no second remover' case_abandoned_token_no_second_remover

report_totals
