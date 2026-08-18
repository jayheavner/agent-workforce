#!/usr/bin/env bash
# tests/lib/dispatch-guard-change-cases.sh — the register-backed half of the dispatch
# guard: a CHANGE declaration claims its workspace, the hook creates or adopts the
# worktree, a foreign live holder is refused, and both crash windows resume instead of
# bricking a slug.
#
# Sourced by tests/test_dispatch_guard.sh after tests/lib/dispatch-guard-fixture.sh;
# sourcing defines these cases and RUNS them, so the whole suite is still one command.
# Split out only for the project's file-size discipline.

# A declared change is claimed in the register and its worktree is created as a side
# effect of the dispatch, so no orchestrator has to create one and no builder is handed
# a path that does not exist.
case_claims_and_creates() {
  dg_fixture claim-new || { printf 'fixture setup failed'; return 1; }
  local cp wt="$PROJ/.claude/worktrees/fresh"
  run "$(dg_payload builder "$(change_prompt fresh)" sess-fresh "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  listed_at "$wt" refs/heads/change/fresh \
    || { printf 'expected git to list %s at refs/heads/change/fresh; observed %s' \
         "$wt" "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
  cp="$(card_path fresh)"
  jq -e '.state == "ready" and .session == "sess-fresh" and .writer.slot == "builder#0"' \
    "$cp" >/dev/null 2>&1 \
    || { printf 'expected a ready card for sess-fresh holding writer builder#0; observed %s' \
         "$(head -c 240 "$cp" 2>/dev/null)"; return 1; }
  [ -f "$(slot_path fresh)" ] || { printf 'expected the writer slot file created'; return 1; }
  return 0
}

case_executor_claims_change() {
  dg_fixture claim-executor || { printf 'fixture setup failed'; return 1; }
  run "$(dg_payload executor "Integrate it.
CHANGE: shipping
" sess-exec "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  listed_at "$PROJ/.claude/worktrees/shipping" refs/heads/change/shipping \
    || { printf 'expected the executor dispatch to build its tree; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
  jq -e '.writer.slot == "executor#0"' "$(card_path shipping)" >/dev/null 2>&1 \
    || { printf 'expected the executor to hold the writer slot; observed %s' \
         "$(head -c 240 "$(card_path shipping)" 2>/dev/null)"; return 1; }
  return 0
}

# A live foreign holder is a durable fact, and the refusal hands the reader every part
# of it plus the escapes, so nobody has to open this hook to know what to do.
case_foreign_holder_refused() {
  dg_fixture foreign-holder || { printf 'fixture setup failed'; return 1; }
  local pid start cp missing=""
  IFS=$'\t' read -r pid start <<< "$(foreign_process)"
  cp="$(write_card busy sess-foreign-holder "$pid" "$start" ready)" \
    || { printf 'could not plant the holder card: %s' "$cp"; return 1; }
  run "$(dg_payload builder "$(change_prompt busy)" sess-mine "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected exit 2 against a live foreign holder; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in *busy*) ;; *) missing="$missing slug" ;; esac
  case "$OUT" in *sess-foreign-holder*) ;; *) missing="$missing holding-session" ;; esac
  case "$OUT" in *"$PROJ/.claude/worktrees/busy"*) ;; *) missing="$missing worktree-path" ;; esac
  case "$OUT" in *"held since"*) ;; *) missing="$missing how-long-held" ;; esac
  case "$OUT" in *WORKFORCE_OVERRIDE*) ;; *) missing="$missing override-escape" ;; esac
  [ -z "$missing" ] || { printf 'expected the refusal to name the holder fact and its escapes; missing:%s observed: %s' \
    "$missing" "$OUT"; return 1; }
  jq -e '.session == "sess-foreign-holder"' "$cp" >/dev/null 2>&1 \
    || { printf 'expected the holder card untouched; observed %s' "$(head -c 200 "$cp")"; return 1; }
  return 0
}

# The refusal above names the human's override line as an escape, so that line has to do
# something: the human, in their own turn, is the one authority that can take a live
# claim from another session. It is honoured and recorded as the fail-open it is — an
# escape that is named and then silently ignored is the retired WORKTREE: marker's defect
# all over again.
case_human_override_takes_the_claim_over() {
  dg_fixture override-claim || { printf 'fixture setup failed'; return 1; }
  local pid start cp tr="$FX/transcript.jsonl" line
  IFS=$'\t' read -r pid start <<< "$(foreign_process)"
  cp="$(write_card contested sess-other-session "$pid" "$start" ready)" \
    || { printf 'could not plant the holder card: %s' "$cp"; return 1; }
  jq -nc --arg t "That claim is stale on my machine; I am releasing it.
WORKFORCE_OVERRIDE: lane-refusal | contested" \
    '{type:"user",message:{role:"user",content:$t}}' > "$tr" || return 1
  run "$(dg_payload executor "Integrate it.
CHANGE: contested
" sess-mine "$PROJ" "$tr")"
  [ "$RC" -eq 0 ] || { printf 'expected the human override honoured; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.session == "sess-mine"' "$cp" >/dev/null 2>&1 \
    || { printf 'expected the change claimed by this session after the override; observed %s' \
         "$(head -c 200 "$cp" 2>/dev/null)"; return 1; }
  line="$(jq -rc 'select(.verdict == "fail-open" and (.detail | test("contested")))' \
    "$GUARD_LOG" 2>/dev/null | tail -n1)"
  case "$line" in
    *sess-other-session*) return 0 ;;
    *) printf 'expected a fail-open record naming the session the claim was taken from; observed %s' \
         "${line:-none}"; return 1 ;;
  esac
}

# BLOCK 5: a dead session's claim never blocks new work, and the tree it left behind is
# adopted rather than fought over. The first dispatch runs inside a killable process
# tree, so the claim it writes really does die with it.
case_reclaim_after_reap_adopts() {
  dg_fixture adopt || { printf 'fixture setup failed'; return 1; }
  local pay="$FX/payload.json" pypid wt="$PROJ/.claude/worktrees/adopted"
  mkdir -p "$FX/out" || return 1
  dg_payload executor "Integrate it.
CHANGE: adopted
" sess-adopt-dead "$PROJ" "" > "$pay"
  python3 -c 'import subprocess,sys,time; subprocess.run(sys.argv[1:]); time.sleep(300)' \
    bash -c "bash '$GUARD' < '$pay' > '$FX/out/dg.out' 2>&1; printf '%s\n' \$? > '$FX/out/dg.rc'" \
    >/dev/null 2>&1 &
  pypid=$!
  note_bg "$pypid"
  if ! wait_for_file "$FX/out/dg.rc" || [ "$(cat "$FX/out/dg.rc")" -ne 0 ]; then
    printf 'expected the first dispatch allowed; observed exit=%s out=%s' \
      "$(cat "$FX/out/dg.rc" 2>/dev/null || printf none)" "$(head -c 200 "$FX/out/dg.out" 2>/dev/null)"
    kill "$pypid" 2>/dev/null; return 1
  fi
  listed_at "$wt" refs/heads/change/adopted \
    || { printf 'expected the tree created by the first dispatch'; kill "$pypid" 2>/dev/null; return 1; }
  kill "$pypid" 2>/dev/null
  wait_for_death "$pypid" || { printf 'expected the holding session process to exit'; return 1; }
  run "$(dg_payload executor "Integrate it.
CHANGE: adopted
" sess-adopt-live "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the re-claim allowed after the reap; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  listed_at "$wt" refs/heads/change/adopted \
    || { printf 'expected the surviving worktree adopted at the same ref; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
  jq -e '.session == "sess-adopt-live"' "$(card_path adopted)" >/dev/null 2>&1 \
    || { printf 'expected a fresh card for the re-claim; observed %s' \
         "$(head -c 200 "$(card_path adopted)" 2>/dev/null)"; return 1; }
  return 0
}

# Window A: the claim is written, the tree cannot be created, so the guard releases the
# card it just wrote — a failed tree creation never leaves a claiming card behind a live
# process, and the same session may retry the same slug once the repair is made.
case_retry_after_tree_failure() {
  dg_fixture retry-tree no || { printf 'fixture setup failed'; return 1; }
  run "$(dg_payload executor "Integrate it.
CHANGE: retry-tree
" sess-retry "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected exit 2 when .claude/worktrees is not gitignored; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in *.gitignore*) ;; *) printf 'expected the refusal to name the .gitignore repair; observed %s' "$OUT"; return 1 ;; esac
  [ -f "$(card_path retry-tree)" ] \
    && { printf 'expected the failed claim released; observed a card at %s' "$(card_path retry-tree)"; return 1; }
  printf '.claude/worktrees/\n' >> "$PROJ/.gitignore"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "chore: ignore the worktree directory" >/dev/null 2>&1
  run "$(dg_payload executor "Integrate it.
CHANGE: retry-tree
" sess-retry "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the retry allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  listed_at "$PROJ/.claude/worktrees/retry-tree" refs/heads/change/retry-tree \
    || { printf 'expected the retry to build the tree; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
  return 0
}

# Window B: a card this same session left in state "claiming" is resumed — the tree is
# completed and the card reaches "ready" — never refused, so one failed dispatch cannot
# brick a slug for the session's life.
case_retry_after_crash_before_ready() {
  dg_fixture resume || { printf 'fixture setup failed'; return 1; }
  local cp wt="$PROJ/.claude/worktrees/crashed"
  cp="$(write_card crashed sess-resume "$$" "$(ps -p "$$" -o lstart=)" claiming)" \
    || { printf 'could not plant the fixture card: %s' "$cp"; return 1; }
  run "$(dg_payload executor "Integrate it.
CHANGE: crashed
" sess-resume "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the same session to resume its claiming card; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  listed_at "$wt" refs/heads/change/crashed \
    || { printf 'expected the resumed dispatch to complete the tree; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
  jq -e '.state == "ready"' "$cp" >/dev/null 2>&1 \
    || { printf 'expected the card state to reach ready; observed %s' \
         "$(jq -r '.state // "unparseable"' "$cp" 2>/dev/null)"; return 1; }
  return 0
}

# The one question this design left to evidence rather than to an unverified harness
# detail: whether a subagent's payload carries its parent session's id, or whether the
# claim resolves by the session process instead. The guard records which branch resolved
# an existing claim, so the first orchestrated task after landing reads the answer out of
# the log instead of assuming it.
case_resumed_claim_records_membership() {
  dg_fixture membership || { printf 'fixture setup failed'; return 1; }
  local cp line
  cp="$(write_card recorded sess-member "$$" "$(ps -p "$$" -o lstart=)" claiming)" \
    || { printf 'could not plant the fixture card: %s' "$cp"; return 1; }
  run "$(dg_payload executor "Integrate it.
CHANGE: recorded
" sess-member "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the resumption allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  line="$(jq -rc 'select(.verdict == "note" and (.detail | test("change=recorded")))' \
    "$GUARD_LOG" 2>/dev/null | tail -n1)"
  case "$line" in
    *membership=pid* | *membership=session-id*) return 0 ;;
    *) printf 'expected a note naming the membership branch that resolved the claim; observed %s' \
         "${line:-none}"; return 1 ;;
  esac
}

# One change, one writer at a time. The second dispatch of the same role for the same
# slug takes the next slot name, and the slot the first one holds is a durable fact.
prior_dispatch_transcript() { # $1 path $2 role $3 slug
  jq -cn --arg r "$2" --arg p "CHANGE: $3" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_prior_1",name:"Agent",input:{subagent_type:$r,prompt:$p}}]}}' \
    > "$1"
}

case_two_live_writers_refused() {
  dg_fixture two-writers || { printf 'fixture setup failed'; return 1; }
  local tr="$FX/transcript.jsonl"
  run "$(dg_payload builder "$(change_prompt shared)" sess-two "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the first builder allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  prior_dispatch_transcript "$tr" builder shared || return 1
  run "$(dg_payload builder "$(change_prompt shared)" sess-two "$PROJ" "$tr")"
  [ "$RC" -eq 2 ] || { printf 'expected the second live writer refused; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in *"builder#0"*) ;; *) printf 'expected the refusal to name the holding slot builder#0; observed %s' "$OUT"; return 1 ;; esac
  case "$OUT" in *writer-release*) ;; *) printf 'expected the refusal to name the command that frees the slot; observed %s' "$OUT"; return 1 ;; esac
  jq -e '.writer.slot == "builder#0"' "$(card_path shared)" >/dev/null 2>&1 \
    || { printf 'expected the first writer still recorded; observed %s' \
         "$(head -c 240 "$(card_path shared)" 2>/dev/null)"; return 1; }
  return 0
}

# A writer that died without releasing its slot cannot hold a change for ever: the slot
# carries its own TTL, and displacing it is a control that stopped enforcing, so it is
# recorded as a fail-open.
case_stale_writer_slot_is_fail_open() {
  dg_fixture stale-writer || { printf 'fixture setup failed'; return 1; }
  local cp lock line
  cp="$(write_card stale sess-stale "$$" "$(ps -p "$$" -o lstart=)" ready)" \
    || { printf 'could not plant the fixture card: %s' "$cp"; return 1; }
  lock="$(slot_path stale)"
  mkdir -p "$(dirname "$lock")" || return 1
  jq -c --argjson hb "$(( $(date +%s) - 5000 ))" \
    '{slot:"builder#9",session:.session,opened:.opened,heartbeat:$hb}' "$cp" > "$lock" || return 1
  run "$(dg_payload builder "$(change_prompt stale)" sess-stale "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the stale slot displaced and the dispatch allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.writer.slot == "builder#0"' "$cp" >/dev/null 2>&1 \
    || { printf 'expected the new writer recorded; observed %s' "$(head -c 240 "$cp")"; return 1; }
  line="$(last_fail_open)"
  case "$line" in
    *builder#9*) ;;
    *) printf 'expected a fail-open record naming the displaced slot builder#9; observed %s' "${line:-none}"; return 1 ;;
  esac
  return 0
}

# A slug that could escape its directory is refused before anything exists to clean up.
case_malformed_slug_refused() {
  dg_fixture bad-slug || { printf 'fixture setup failed'; return 1; }
  local s trees
  for s in '../escape' 'Bad Slug' 'has/slash' 'UPPER' 'foo.lock' 'trailing.'; do
    run "$(dg_payload executor "Integrate it.
CHANGE: $s
" sess-bad "$PROJ" "")"
    [ "$RC" -eq 2 ] || { printf 'expected exit 2 for the slug "%s"; observed exit=%s out=%s' "$s" "$RC" "$OUT"; return 1; }
    case "$OUT" in
      *"lower-case"*) ;;
      *) printf 'expected the refusal to state the legal slug shape for "%s"; observed %s' "$s" "$OUT"; return 1 ;;
    esac
  done
  trees="$(git -C "$PROJ" worktree list --porcelain | grep -c '^worktree ')"
  [ "$trees" = "1" ] || { printf 'expected no worktree created; observed %s registered' "$trees"; return 1; }
  return 0
}

run_case 'a builder dispatch declaring a new change claims it and creates the tree' case_claims_and_creates
run_case 'an executor dispatch declaring a change claims it' case_executor_claims_change
run_case 'the same slug from a foreign live session is refused with the holder named' case_foreign_holder_refused
run_case 'a human override of a live foreign claim takes it over as a fail-open' case_human_override_takes_the_claim_over
run_case 're-claim after reap adopts the surviving worktree' case_reclaim_after_reap_adopts
run_case 'a retry after a failed tree creation re-claims the same slug' case_retry_after_tree_failure
run_case 'a retry after a crash before ready completes the claim' case_retry_after_crash_before_ready
run_case 'a resumed claim records which membership branch resolved it' case_resumed_claim_records_membership
run_case 'two live writers on one change are refused' case_two_live_writers_refused
run_case 'a second writer slot after the TTL is granted and logged as a fail-open' case_stale_writer_slot_is_fail_open
run_case 'a malformed slug is refused before anything is created' case_malformed_slug_refused
