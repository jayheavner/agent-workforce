#!/usr/bin/env bash
# tests/lib/dispatch-guard-writer-cases.sh — the writing turn itself: when a change's
# writer slot is released, when it is kept, when it is never taken at all, and what a
# dispatch the guard refuses leaves behind.
#
# Why these cases exist. Nothing released a writer slot on normal completion, so the
# ordinary sequential flow on ONE change — a builder, then the executor that integrates
# it — was refused until the slot's TTL lapsed. And the gate's side effects ran before
# the budget checkpoint, so a checkpoint-blocked dispatch stranded a claim, a worktree
# and a phantom writer slot that then refused the honest retry.
#
# Sourced by tests/test_dispatch_guard.sh after tests/lib/dispatch-guard-fixture.sh,
# tests/lib/dispatch-guard-change-cases.sh (whose `prior_dispatch_transcript` these
# reuse) and the budget-ratchet section (whose `write_resolved_dispatches_transcript`
# the checkpoint case reuses); sourcing defines these cases and RUNS them, so the whole
# suite is still one command. Split out only for the project's file-size discipline.

# What "finished" looks like on disk: one dispatch AND its tool result.
resolved_dispatch_transcript() { # $1 path $2 role $3 slug
  { jq -cn --arg r "$2" --arg p "CHANGE: $3" \
      '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_done_1",name:"Agent",input:{subagent_type:$r,prompt:$p}}]}}'
    jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_done_1",content:[{type:"text",text:"WORKFORCE_REPORT: builder | complete"}]}]}}'
  } > "$1"
}

# The demonstrated defect, inverted into a case: builder then executor on ONE change.
case_resolved_slot_released_before_acquire() {
  dg_fixture release-resolved || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" line
  run "$(dg_payload builder "$(change_prompt handoff)" sess-handoff "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "builder#0"' "$(slot_path handoff)" >/dev/null 2>&1 \
    || { printf 'expected builder#0 holding the slot; observed %s' "$(head -c 200 "$(slot_path handoff)" 2>/dev/null)"; return 1; }
  resolved_dispatch_transcript "$tr" builder handoff || return 1
  run "$(dg_payload executor "Integrate it.
CHANGE: handoff
" sess-handoff "$PROJ" "$tr")"
  [ "$RC" -eq 0 ] || { printf 'expected the executor allowed after the builder finished; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "executor#0"' "$(slot_path handoff)" >/dev/null 2>&1 \
    || { printf 'expected the executor holding the slot; observed %s' "$(head -c 200 "$(slot_path handoff)" 2>/dev/null)"; return 1; }
  line="$(jq -rc 'select(.verdict == "note" and (.detail | test("released")))' "$GUARD_LOG" 2>/dev/null | tail -n1)"
  case "$line" in
    *"builder#0"*) return 0 ;;
    *) printf 'expected a note recording the released slot builder#0; observed %s' "${line:-none}"; return 1 ;;
  esac
}

# The same sequence read as the flow it is, with no log assertion: the ordinary
# hand-off on one change is not refused, which is the outcome AC-4 names.
case_builder_then_executor_both_proceed() {
  dg_fixture sequential-flow || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl"
  run "$(dg_payload builder "$(change_prompt sequence)" sess-sequence "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  resolved_dispatch_transcript "$tr" builder sequence || return 1
  run "$(dg_payload executor "Integrate it.
CHANGE: sequence
" sess-sequence "$PROJ" "$tr")"
  [ "$RC" -eq 0 ] || { printf 'expected the executor allowed on the same change; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  listed_at "$PROJ/.claude/worktrees/sequence" refs/heads/change/sequence \
    || { printf 'expected both dispatches to share the one tree; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
  return 0
}

# The exclusion still holds while somebody is behind the slot, and the log says why.
case_in_flight_slot_kept() {
  dg_fixture keep-in-flight || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl" line
  run "$(dg_payload builder "$(change_prompt busy-tree)" sess-keep "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  prior_dispatch_transcript "$tr" builder busy-tree || return 1
  run "$(dg_payload executor "Integrate it.
CHANGE: busy-tree
" sess-keep "$PROJ" "$tr")"
  [ "$RC" -eq 2 ] || { printf 'expected the executor refused while the builder is in flight; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "builder#0"' "$(slot_path busy-tree)" >/dev/null 2>&1 \
    || { printf 'expected builder#0 still holding the slot; observed %s' "$(head -c 200 "$(slot_path busy-tree)" 2>/dev/null)"; return 1; }
  line="$(jq -rc 'select(.verdict == "note" and (.detail | test("kept")))' "$GUARD_LOG" 2>/dev/null | tail -n1)"
  case "$line" in
    *"in flight"*) return 0 ;;
    *) printf 'expected a note recording the slot kept for an in-flight dispatch; observed %s' "${line:-none}"; return 1 ;;
  esac
}

# No transcript is no evidence, and no evidence releases nothing: the pre-existing TTL wait
# stands rather than a guess removing a live writer's exclusion.
case_unreadable_transcript_releases_nothing() {
  dg_fixture no-transcript || { printf 'fixture setup failed'; return 1; }
  run "$(dg_payload builder "$(change_prompt sealed)" sess-sealed "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  run "$(dg_payload executor "Integrate it.
CHANGE: sealed
" sess-sealed "$PROJ" "$FX/absent.jsonl")"
  [ "$RC" -eq 2 ] || { printf 'expected the executor refused with no transcript to read; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "builder#0"' "$(slot_path sealed)" >/dev/null 2>&1 \
    || { printf 'expected the slot untouched; observed %s' "$(head -c 200 "$(slot_path sealed)" 2>/dev/null)"; return 1; }
  return 0
}

# A judge holds no writing turn, so it is neither refused for one nor granted one. This is
# the case that fails if WRITER_SLOT_ROLES is forgotten.
case_judge_takes_no_writer_slot() {
  dg_fixture judge-no-slot || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl"
  run "$(dg_payload builder "$(change_prompt judged)" sess-judge "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  prior_dispatch_transcript "$tr" builder judged || return 1
  run "$(dg_payload verifier "Verify it.
CHANGE: judged
$CRITERIA_BODY" sess-judge "$PROJ" "$tr")"
  [ "$RC" -eq 0 ] || { printf 'expected the verifier allowed beside a live builder; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "builder#0"' "$(slot_path judged)" >/dev/null 2>&1 \
    || { printf 'expected the builder still holding the only writing turn; observed %s' "$(head -c 200 "$(slot_path judged)" 2>/dev/null)"; return 1; }
  return 0
}

# A dispatch the budget checkpoint refuses must leave the register exactly as it found
# it. The gate's side effects ran first, so the refused tenth dispatch claimed the
# change, built the tree and took builder#0 — and the honest retry then computed
# builder#1, found builder#0 fresh, and was refused for a writer that never existed.
case_checkpoint_block_strands_nothing() {
  dg_fixture checkpoint-strand || { printf 'fixture setup failed'; return 1; }
  local tr trees
  tr="$(write_resolved_dispatches_transcript 9)"
  run "$(dg_payload builder "$(change_prompt tenth)" sess-checkpoint "$PROJ" "$tr")"
  [ "$RC" -eq 2 ] || { printf 'expected the tenth dispatch refused at the checkpoint; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in
    *checkpoint*) ;;
    *) printf 'expected the checkpoint refusal rather than another; observed %s' "$OUT"; return 1 ;;
  esac
  if [ -f "$(card_path tenth)" ]; then
    printf 'expected no claim left behind; observed a card at %s' "$(card_path tenth)"; return 1
  fi
  if [ -f "$(slot_path tenth)" ]; then
    printf 'expected no writer slot left behind; observed one at %s' "$(slot_path tenth)"; return 1
  fi
  trees="$(git -C "$PROJ" worktree list --porcelain | grep -c '^worktree ')"
  [ "$trees" = "1" ] \
    || { printf 'expected no worktree created; observed %s registered' "$trees"; return 1; }
  return 0
}

# THE WRITER-SLOT FALSE GRANT, closed. Two builder dispatches on one change, in one
# session, with no transcript to count from: both compute the slot name `builder#0`, and
# both used to be granted the writing turn — the second read as the first re-entering,
# because the session and the card's `opened` stamp are identical for the pair. The slot
# now also records an identifier of the dispatch that took it, so a sibling is refused
# and the holder keeps its turn.
case_sibling_dispatch_refused_the_writing_turn() {
  dg_fixture sibling-writer || { printf 'fixture setup failed'; return 1; }
  run "$(dg_payload builder "$(change_prompt shared-turn)" sess-sibling "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the first builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  run "$(dg_payload builder "Implement the other half.
CHANGE: shared-turn
$CRITERIA_BODY" sess-sibling "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected the sibling dispatch refused the writing turn; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in
    *'live writer'*) ;;
    *) printf 'expected the refusal to name the live writer; observed %s' "$OUT"; return 1 ;;
  esac
  jq -e '.slot == "builder#0" and (.dispatch | length) > 0' "$(slot_path shared-turn)" >/dev/null 2>&1 \
    || { printf 'expected the first dispatch still recorded as the holder; observed %s' \
         "$(head -c 200 "$(slot_path shared-turn)" 2>/dev/null)"; return 1; }
  return 0
}

# And the case the discriminator must NOT break: one dispatch whose guard runs twice —
# the same payload, byte for byte — is the same writer re-entering its own slot, not a
# second one, and it is granted.
case_same_dispatch_reenters_its_own_slot() {
  dg_fixture reenter-writer || { printf 'fixture setup failed'; return 1; }
  local payload
  payload="$(dg_payload builder "$(change_prompt re-entered)" sess-reenter "$PROJ" "")"
  run "$payload"
  [ "$RC" -eq 0 ] || { printf 'expected the first run allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  run "$payload"
  [ "$RC" -eq 0 ] || { printf 'expected the identical payload allowed as re-entry; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "builder#0"' "$(slot_path re-entered)" >/dev/null 2>&1 \
    || { printf 'expected the one slot still held by builder#0; observed %s' \
         "$(head -c 200 "$(slot_path re-entered)" 2>/dev/null)"; return 1; }
  return 0
}

run_case "a resolved dispatch's writer slot is released before the next one acquires" \
  case_resolved_slot_released_before_acquire
run_case 'a builder then an executor on one change both proceed' \
  case_builder_then_executor_both_proceed
run_case "an in-flight dispatch's writer slot is kept and the refusal stands" \
  case_in_flight_slot_kept
run_case 'an unreadable transcript releases no writer slot' \
  case_unreadable_transcript_releases_nothing
run_case 'a judge dispatch declaring a change takes no writer slot' \
  case_judge_takes_no_writer_slot
run_case 'a checkpoint-blocked dispatch strands no claim and no writer slot' \
  case_checkpoint_block_strands_nothing
run_case 'a sibling dispatch on one change is refused the writing turn' \
  case_sibling_dispatch_refused_the_writing_turn
run_case "the same dispatch re-entering its own writer slot is granted" \
  case_same_dispatch_reenters_its_own_slot

# --- a displacement is never quieter than a refusal --------------------------
# A slot planted by hand: the holder's name, the dispatch that took it, a heartbeat as old
# as the case needs. Session and `opened` come from the card, so the slot reads as this
# claim's own incarnation and the DISPATCH is the only fact separating the two.
plant_writer_slot() { # $1 card $2 slot $3 dispatch $4 age-seconds
  local lock
  lock="$(dirname "$1")/writers/$(basename "$1")"
  mkdir -p "$(dirname "$lock")" || return 1
  jq -c --arg slot "$2" --arg disp "$3" --argjson hb "$(( $(date +%s) - $4 ))" \
    '{slot:$slot,session:.session,opened:.opened,dispatch:$disp,heartbeat:$hb}' "$1" > "$lock"
}

# How many fail-opens the guard recorded about ONE change: the log is the suite's one file,
# so a case counts only the lines naming its own slug.
fail_opens_naming() { # $1 slug -> count
  [ -f "$GUARD_LOG" ] || { printf 0; return 0; }
  jq -rs --arg s "$1" \
    '[ .[] | select(.verdict == "fail-open" and (.detail | contains($s))) ] | length' \
    "$GUARD_LOG" 2>/dev/null
}

# A card planted live with a lapsed slot beside it: where every displacement case starts.
lapsed_slot_fixture() { # $1 fixture $2 slug $3 session $4 slot $5 dispatch -> sets CARD
  dg_fixture "$1" || { printf 'fixture setup failed'; return 1; }
  CARD="$(write_card "$2" "$3" "$$" "$(ps -p "$$" -o lstart=)" ready)" \
    || { printf 'could not plant the fixture card: %s' "$CARD"; return 1; }
  plant_writer_slot "$CARD" "$4" "$5" 5000 || { printf 'could not plant the slot'; return 1; }
}

# A DISPLACEMENT NOBODY RECORDED. The slot name is `<role>#<n>` counted from a transcript,
# so the likeliest collision is two dispatches computing the SAME name: with no transcript
# to count from this dispatch computes `builder#0` and the lapsed holder is `builder#0` too.
# The record was keyed on the name, so it stayed silent exactly there — while the dispatch
# digest, which exists because the name cannot tell two dispatches apart, said plainly that
# the slot had changed hands.
case_same_name_displacement_recorded() {
  local line
  lapsed_slot_fixture same-name-displace collided sess-collide 'builder#0' 0123456789abcdef || return 1
  run "$(dg_payload builder "$(change_prompt collided)" sess-collide "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the lapsed slot displaced and the dispatch allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.slot == "builder#0" and .dispatch != "0123456789abcdef"' "$(slot_path collided)" >/dev/null 2>&1 \
    || { printf 'expected this dispatch recorded as the holder; observed %s' "$(head -c 200 "$(slot_path collided)" 2>/dev/null)"; return 1; }
  line="$(last_fail_open)"
  case "$line" in *0123456789abcdef*) ;; *) printf 'expected a fail-open naming the displaced dispatch; observed %s' "${line:-none}"; return 1 ;; esac
  case "$line" in *collided*) return 0 ;; *) printf 'expected the fail-open to name the change; observed %s' "$line"; return 1 ;; esac
}

# The boundary that record must not cross: one dispatch whose guard runs twice is the same
# writer re-entering its own slot — same name, same digest, nothing taken from anybody, and
# a fail-open there is a false alarm in a log whose value is that a fail-open means one.
case_reentry_records_no_fail_open() {
  local payload after
  dg_fixture reentry-quiet || { printf 'fixture setup failed'; return 1; }
  payload="$(dg_payload builder "$(change_prompt quiet-reentry)" sess-quiet "$PROJ" "")"
  run "$payload"
  [ "$RC" -eq 0 ] || { printf 'expected the first run allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  run "$payload"
  [ "$RC" -eq 0 ] || { printf 'expected the identical payload allowed as re-entry; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  after="$(fail_opens_naming quiet-reentry)"
  [ "$after" = "0" ] || { printf 'expected no fail-open for a re-entry; observed %s: %s' "$after" \
    "$(jq -rc 'select(.verdict == "fail-open")' "$GUARD_LOG" | tail -n1)"; return 1; }
  return 0
}

# THE FIFTEEN-MINUTE WRITER. Nothing refreshes a heartbeat during work, so a slot lapses
# while its holder is honestly building, and the TTL then handed the writing turn to a
# second dispatch on the same change. The gate holds the fact that settles it — the holder's
# dispatch is unresolved in this session's transcript — and a timeout is for a writer nobody
# is behind, never for a live one.
case_in_flight_writer_not_displaced_by_ttl() {
  local tr
  lapsed_slot_fixture live-writer-ttl grinding sess-grind 'builder#1' aaaabbbbccccdddd || return 1
  tr="$FX/transcript.jsonl"
  prior_dispatch_transcript "$tr" builder grinding || return 1
  run "$(dg_payload builder "$(change_prompt grinding)" sess-grind "$PROJ" "$tr")"
  [ "$RC" -eq 2 ] || { printf 'expected the second writer refused while the holder is in flight; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.dispatch == "aaaabbbbccccdddd"' "$(slot_path grinding)" >/dev/null 2>&1 \
    || { printf 'expected the in-flight holder still recorded; observed %s' "$(head -c 200 "$(slot_path grinding)" 2>/dev/null)"; return 1; }
  case "$OUT" in *'in flight'*) return 0 ;; *) printf 'expected the refusal to say the holder is still in flight; observed %s' "$OUT"; return 1 ;; esac
}

# And the crash path that must stay open: the holder's dispatch has RESOLVED, so nobody is
# behind the lapsed slot and the change must not be wedged by it. This is the case that
# fails if "never displace a live writer" is read as "never displace".
case_resolved_stale_slot_still_displaceable() {
  local tr gone
  lapsed_slot_fixture resolved-stale crashed sess-crash 'builder#9' eeeeffff00001111 || return 1
  tr="$FX/transcript.jsonl"
  resolved_dispatch_transcript "$tr" builder crashed || return 1
  run "$(dg_payload builder "$(change_prompt crashed)" sess-crash "$PROJ" "$tr")"
  [ "$RC" -eq 0 ] || { printf 'expected the lapsed slot recovered once its dispatch resolved; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.dispatch != "eeeeffff00001111"' "$(slot_path crashed)" >/dev/null 2>&1 \
    || { printf 'expected the new dispatch holding the slot; observed %s' "$(head -c 200 "$(slot_path crashed)" 2>/dev/null)"; return 1; }
  gone="$(jq -rs '[ .[] | select(.detail | contains("builder#9")) ] | length' "$GUARD_LOG" 2>/dev/null)"
  [ "${gone:-0}" -ge 1 ] || { printf 'expected the log to record that builder#9 stopped holding the slot'; return 1; }
  return 0
}

# Where the record has to land. A message on stderr reaches one agent and is gone; the
# fail-open has to accumulate somewhere an operator can count it. The directory asserted
# against is the fixture's own, inside this run's temporary tree — never the machine's.
case_displacement_fail_open_reaches_the_log() {
  lapsed_slot_fixture logged-displacement log-sink sess-logged 'builder#0' 2222333344445555 || return 1
  case "$AGENT_TEAM_TELEMETRY_DIR" in "$WORK"/*) ;;
    *) printf 'the fixture telemetry directory %s is not inside this run own tree %s' "$AGENT_TEAM_TELEMETRY_DIR" "$WORK"; return 1 ;; esac
  [ "$GUARD_LOG" = "$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl" ] \
    || { printf 'expected the guard log at %s; observed %s' "$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl" "$GUARD_LOG"; return 1; }
  run "$(dg_payload builder "$(change_prompt log-sink)" sess-logged "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the lapsed slot displaced and the dispatch allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  [ "$(fail_opens_naming log-sink)" -ge 1 ] \
    || { printf 'expected a fail-open naming this change in %s; observed none' "$GUARD_LOG"; return 1; }
  grep -q 2222333344445555 "$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl" \
    || { printf 'expected the displaced dispatch named in the log file itself'; return 1; }
  return 0
}

run_case 'a displacement of a same-named slot from another dispatch is recorded as a fail-open' \
  case_same_name_displacement_recorded
run_case 'the same dispatch re-entering its own writer slot records no fail-open' \
  case_reentry_records_no_fail_open
run_case 'a writer slot held by an in-flight dispatch is not displaced by the TTL' \
  case_in_flight_writer_not_displaced_by_ttl
run_case 'a stale slot whose dispatch resolved is still displaceable' \
  case_resolved_stale_slot_still_displaceable
run_case 'the displacement fail-open is written to the guard log' \
  case_displacement_fail_open_reaches_the_log
