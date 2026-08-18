#!/usr/bin/env bash
# tests/test_closeout_hook.sh — behavior and coverage gate for the closeout
# Stop hook. Two parts, both measured:
#
#   1. the unittest behavior suite (tests/test_agent_team_closeout.py), which
#      drives the hook as a subprocess the way the harness does;
#   2. the labeled change-disposition scenarios below, which need a real git
#      project, a real change worktree and a real timecard in a private work
#      register — fixtures a unittest temp dir cannot express as cheaply as a
#      shell can. Each prints `PASS [<label>]` or `FAIL [<label>]: <why>`.
#
# Subprocess runs in both parts are measured with coverage's parallel mode and
# combined before reporting. Threshold is 80: the hook has deliberate
# fail-open branches (state I/O errors, cost-report subprocess failures)
# that a behavior test cannot reach without an unreasonable amount of fault
# injection.
#
# Nothing here touches machine state: every git mutation happens inside a
# mktemp fixture repository, and AGENT_TEAM_REGISTER_DIR points at a fixture
# register, so no real claim is ever read, written or reaped.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DATA_DIR="$(mktemp -d)"
trap 'rm -rf "$DATA_DIR"' EXIT
export COVERAGE_FILE="$DATA_DIR/.coverage"
HOOK="$ROOT/hooks/agent_team_closeout.py"
REG_SH="$ROOT/hooks/agent-team-register.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'PASS [%s]\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL [%s]: %s\n' "$1" "$2"; }

# --- part 1: the unittest behavior suite -------------------------------------
UNIT_OUT="$DATA_DIR/unittest.out"
set -o pipefail
COVERAGE_HOOK_SUBPROCESS=1 python3 -m coverage run --parallel-mode \
  --source="$ROOT/hooks" "$HERE/test_agent_team_closeout.py" 2>&1 | tee "$UNIT_OUT"
UNIT_RC=$?
set +o pipefail

# --- part 2: the change-disposition scenarios -------------------------------
COST_TAIL='

## Cost report

| Model | Cost |
'

fixture() { # $1 name -> sets FX, PROJ; exports the fixture register dir
  FX="$DATA_DIR/$1"
  PROJ="$FX/proj"
  mkdir -p "$PROJ" "$FX/register" || return 1
  chmod 700 "$FX/register"
  export AGENT_TEAM_REGISTER_DIR="$FX/register"
  git -C "$PROJ" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$PROJ" config user.email "closeout@example.invalid"
  git -C "$PROJ" config user.name "Closeout Fixture"
  mkdir -p "$PROJ/docs"
  printf '.claude/worktrees/\n' > "$PROJ/.gitignore"
  printf 'note\n' > "$PROJ/docs/note.md"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "init: fixture project" >/dev/null 2>&1 || return 1
  PROJ="$(cd "$PROJ" && pwd -P)"
  mkdir -p "$PROJ/.claude/worktrees"
}

mk_worktree() { # $1 slug -> prints the change worktree path
  local wt="$PROJ/.claude/worktrees/$1"
  git -C "$PROJ" worktree add -q "$wt" -b "change/$1" main >/dev/null 2>&1 || return 1
  printf '%s' "$wt"
}

# A docs-only commit, so the hook's code-separation checks stay quiet and the
# only thing under test is the change disposition.
change_commit() { # $1 worktree
  printf 'changed by the change\n' > "$1/docs/note.md"
  git -C "$1" add -A >/dev/null 2>&1 || return 1
  git -C "$1" commit -qm "docs: work inside the change" >/dev/null 2>&1
}

# The card path comes from the register itself, so this suite never re-derives
# the project-key hash.
write_card() { # $1 slug $2 session $3 state $4 worktree -> prints the card path
  local cp key base
  cp="$(bash "$REG_SH" card-path "$PROJ" "$1" 2>&1)" || { printf '%s' "$cp"; return 1; }
  mkdir -p "$(dirname "$cp")" || return 1
  key="$(basename "$(dirname "$cp")")"
  base="$(git -C "$PROJ" rev-parse HEAD)"
  jq -n --arg slug "$1" --arg proj "$PROJ" --arg key "$key" --arg sess "$2" \
    --argjson pid "$$" --arg start "$(ps -p "$$" -o lstart=)" --arg wt "$4" \
    --arg ref "refs/heads/change/$1" --arg base "$base" --arg state "$3" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:"refs/heads/main",
      base_sha:$base,state:$state,opened:$opened,heartbeat:$hb,writer:null}' \
    > "$cp" || return 1
  printf '%s' "$cp"
}

co_transcript() { # $1 path $2 final message text — one scribe dispatch, resolved
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

run_closeout() { # $1 transcript $2 session -> sets COUT, CO_DECISION, CO_REASON
  local pay
  pay="$(jq -cn --arg tr "$1" --arg cwd "$PROJ" --arg sid "$2" \
    '{session_id:$sid,transcript_path:$tr,cwd:$cwd}')"
  COUT="$(printf '%s' "$pay" | env \
    AGENT_TEAM_CLOSEOUT_STATE="$FX/closeout-state" \
    AGENT_TEAM_COST_DIR="$FX/cost" \
    AGENT_TEAM_TELEMETRY_DIR="$FX/telemetry" \
    AGENT_TEAM_CLOSEOUT_RETRY_DELAY=0 \
    python3 -m coverage run --parallel-mode --source="$ROOT/hooks" \
    "$HOOK" 2>/dev/null)"
  CO_DECISION="$(printf '%s' "$COUT" | jq -r '.decision // ""' 2>/dev/null || printf '')"
  CO_REASON="$(printf '%s' "$COUT" | jq -r '.reason // ""' 2>/dev/null || printf '')"
}

# (a) The Stop hook is a verifier: it may block, and it may not integrate.
LABEL='a bare Stop with a live claim integrates nothing'
if ! fixture bare-stop; then
  bad "$LABEL" "fixture setup failed"
else
  WT="$(mk_worktree held)" && change_commit "$WT" \
    && CARD="$(write_card held sess-bare ready "$WT")" || CARD=""
  if [ -z "$CARD" ] || [ ! -f "$CARD" ]; then
    bad "$LABEL" "could not build the fixture claim"
  else
    BEFORE_WT="$(git -C "$PROJ" worktree list --porcelain)"
    BEFORE_HEAD="$(git -C "$PROJ" rev-parse HEAD)"
    BEFORE_CARD="$(cat "$CARD")"
    co_transcript "$FX/transcript.jsonl" "Paused here; nothing else to report."
    run_closeout "$FX/transcript.jsonl" sess-bare
    WHY=""
    [ "$BEFORE_WT" = "$(git -C "$PROJ" worktree list --porcelain)" ] \
      || WHY="$WHY worktree-registration-changed"
    [ "$BEFORE_HEAD" = "$(git -C "$PROJ" rev-parse HEAD)" ] \
      || WHY="$WHY shared-HEAD-moved"
    { [ -f "$CARD" ] && [ "$BEFORE_CARD" = "$(cat "$CARD")" ]; } \
      || WHY="$WHY timecard-touched"
    git -C "$PROJ" show-ref --verify --quiet refs/heads/change/held \
      || WHY="$WHY ref-deleted"
    case "$CO_REASON" in *held*) ;; *) WHY="$WHY block-does-not-name-the-claim" ;; esac
    [ -z "$WHY" ] && ok "$LABEL" \
      || bad "$LABEL" "$WHY (reason: $(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-200))"
  fi
fi

# (b) A completion claim while a change is held must state its disposition.
LABEL='a completion claim with no change disposition is blocked'
CARD="$(write_card held sess-bare-b ready "$WT")"
co_transcript "$FX/completion.jsonl" "Delivered the work.$COST_TAIL"
run_closeout "$FX/completion.jsonl" sess-bare-b
if [ "$CO_DECISION" != "block" ]; then
  bad "$LABEL" "expected decision=block; observed decision=${CO_DECISION:-none}"
else
  case "$CO_REASON" in
    *"CHANGE-DISPOSITION: held"*) ok "$LABEL" ;;
    *) bad "$LABEL" "block does not hand over the exact line (reason: $(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-250))" ;;
  esac
fi

# (c) A mid-task pause demands nothing: the marker skips the check entirely.
LABEL='a HUMAN_DECISION pause with a live claim is allowed'
CARD="$(write_card held sess-bare-c ready "$WT")"
co_transcript "$FX/pause.jsonl" \
  "Stopping for a decision.
WORKFORCE_PAUSE: HUMAN_DECISION$COST_TAIL"
run_closeout "$FX/pause.jsonl" sess-bare-c
if [ -n "$CO_DECISION" ]; then
  bad "$LABEL" "expected no block on a pause; observed decision=$CO_DECISION reason=$(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-200)"
else
  ok "$LABEL"
fi

# (d) "integrated" is verified against git, never believed.
LABEL='an integrated disposition whose ref is not an ancestor is blocked'
if ! fixture integrated; then
  bad "$LABEL" "fixture setup failed"
else
  WT="$(mk_worktree verify)" && change_commit "$WT" \
    && CARD="$(write_card verify sess-int-a ready "$WT")" || CARD=""
  co_transcript "$FX/transcript.jsonl" "Delivered.
CHANGE-DISPOSITION: verify | integrated into refs/heads/main$COST_TAIL"
  run_closeout "$FX/transcript.jsonl" sess-int-a
  if [ "$CO_DECISION" != "block" ]; then
    bad "$LABEL" "expected decision=block for an unmerged ref; observed decision=${CO_DECISION:-none}"
  else
    case "$CO_REASON" in
      *verify*) ok "$LABEL" ;;
      *) bad "$LABEL" "block does not name the change (reason: $(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-250))" ;;
    esac
  fi

  # (e) The merge really happened, but the timecard is still there — so the
  #     integration command never ran to completion.
  LABEL='an integrated disposition whose timecard still exists is blocked'
  if ! git -C "$PROJ" merge --no-ff --no-edit change/verify >/dev/null 2>&1; then
    bad "$LABEL" "fixture merge failed"
  else
    CARD="$(write_card verify sess-int-b ready "$WT")"
    run_closeout "$FX/transcript.jsonl" sess-int-b
    if [ "$CO_DECISION" != "block" ]; then
      bad "$LABEL" "expected decision=block while the card survives; observed decision=${CO_DECISION:-none}"
    else
      case "$CO_REASON" in
        *agent-team-workspace.sh*)
          # ...and once the card is released, the same claim is a verified fact.
          rm -f "$CARD"
          run_closeout "$FX/transcript.jsonl" sess-int-c
          case "$CO_REASON" in
            *verify*) bad "$LABEL" "still blocked after the card was released: $(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-200)" ;;
            *) ok "$LABEL" ;;
          esac
          ;;
        *) bad "$LABEL" "block does not name the integrating command (reason: $(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-250))" ;;
      esac
    fi
  fi
fi

# (f) A stated disposition that is not an integration claim needs no git proof.
LABEL='a kept disposition citing a tracker reference is allowed'
if ! fixture kept; then
  bad "$LABEL" "fixture setup failed"
else
  WT="$(mk_worktree parked)" && change_commit "$WT" \
    && CARD="$(write_card parked sess-kept ready "$WT")" || CARD=""
  co_transcript "$FX/transcript.jsonl" "Delivered what was asked.
CHANGE-DISPOSITION: parked | kept for #42$COST_TAIL"
  run_closeout "$FX/transcript.jsonl" sess-kept
  if [ -n "$CO_DECISION" ]; then
    bad "$LABEL" "expected no block for a kept disposition; observed reason=$(printf '%s' "$CO_REASON" | tr '\n' ' ' | cut -c1-250)"
  else
    ok "$LABEL"
  fi
fi

# --- the coverage gate ------------------------------------------------------
python3 -m coverage combine >/dev/null || FAIL=$((FAIL + 1))
python3 -m coverage report \
  --include="$ROOT/hooks/agent_team_closeout.py,$ROOT/hooks/agent_team_closeout_paths.py,$ROOT/hooks/agent_team_closeout_ledger.py" \
  --fail-under=80 || FAIL=$((FAIL + 1))

if [ "$UNIT_RC" -ne 0 ]; then
  printf 'FAIL [the unittest behavior suite]: exit=%s (see the output above)\n' "$UNIT_RC"
  FAIL=$((FAIL + 1))
fi

printf 'closeout hook tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
