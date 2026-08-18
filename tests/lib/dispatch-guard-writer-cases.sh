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
