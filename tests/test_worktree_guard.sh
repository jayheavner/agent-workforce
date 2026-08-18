#!/usr/bin/env bash
# tests/test_worktree_guard.sh — the worktree guard: which change governs the agent
# that is acting, and which writes and shell commands that change makes legal.
#
# Output contract: one line per case, `PASS [<label>]` or `FAIL [<label>]: <why>`,
# then a trailing `passed=<n> failed=<n>`. Exit is non-zero when any case failed.
#
# WHERE CONFINEMENT COMES FROM. Until this suite was rewritten, it came from the
# transcript: the guard read a `WORKTREE: <path>` line and had to guess which of a
# main session's many declarations was this agent's. On 2026-08-04 that guess was
# the oldest line in the file — one malformed path poisoned six later dispatches,
# and no dispatch could have repaired it. Confinement now comes from the WORK
# REGISTER: the live timecards this session holds are the candidate set, and this
# agent's own dispatch prompt is only a selector among them. Ambiguity is a refusal
# that names every candidate, never a pick by recency.
#
# Safety contract: every case points AGENT_TEAM_REGISTER_DIR and
# AGENT_TEAM_TELEMETRY_DIR inside its own throwaway fixture, so no run of this
# suite reads or writes the machine's own register, telemetry, or agent memory.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-worktree-guard.sh"
REG_SH="$HERE/../hooks/agent-team-register.sh"
WS_SH="$HERE/../hooks/agent-team-workspace.sh"
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf 'PASS [%s]\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL [%s]: %s\n' "$1" "$2"; }
brief() { printf '%s' "$1" | tr '\n\t' '  ' | cut -c1-240; }

# The guard, run on a payload: sets GOUT (stdout+stderr) and GRC.
run_guard() { # $1 role $2 payload
  GOUT="$(printf '%s' "$2" | bash "$GUARD" "$1" 2>&1)"
  GRC=$?
  return 0
}

expect() { # $1 expected_rc $2 role $3 payload $4 label
  run_guard "$2" "$3"
  if [ "$GRC" -eq "$1" ]; then
    pass "$4"
  else
    fail "$4" "expected exit $1, observed exit $GRC: $(brief "$GOUT")"
  fi
}
allow() { expect 0 "$1" "$2" "$3"; }
block() { expect 2 "$1" "$2" "$3"; }

# A refusal is only useful when a reader can act on it, so the message is part of
# the assertion: exit 2 AND every named fact.
block_naming() { # $1 role $2 payload $3 label $4... substrings the message must carry
  local role="$1" payload="$2" label="$3" missing="" want
  shift 3
  run_guard "$role" "$payload"
  if [ "$GRC" -ne 2 ]; then
    fail "$label" "expected exit 2, observed exit $GRC: $(brief "$GOUT")"
    return 0
  fi
  for want in "$@"; do
    case "$GOUT" in *"$want"*) ;; *) missing="$missing '$want'" ;; esac
  done
  if [ -n "$missing" ]; then
    fail "$label" "the refusal named neither$missing: $(brief "$GOUT")"
  else
    pass "$label"
  fi
}

# --- the world every case runs in -------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/worktree-guard.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT INT TERM
MAIN="$WORK/main"
REGDIR="$WORK/register"
export AGENT_TEAM_REGISTER_DIR="$REGDIR"
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry"
mkdir -p "$MAIN" "$REGDIR"
chmod 700 "$REGDIR"
git -C "$MAIN" init -q -b main
git -C "$MAIN" config user.email t@example.com
git -C "$MAIN" config user.name Test
mkdir -p "$MAIN/docs" "$MAIN/plans" "$MAIN/tests/acceptance"
printf 'x\n' > "$MAIN/file.txt"
printf 'note\n' > "$MAIN/docs/note.md"
git -C "$MAIN" add -A
git -C "$MAIN" commit -qm init
mkdir -p "$MAIN/.claude/worktrees"
WT_MINE="$MAIN/.claude/worktrees/task-a"
WT_OTHER="$MAIN/.claude/worktrees/task-b"
git -C "$MAIN" worktree add -q "$WT_MINE" -b change/task-a
git -C "$MAIN" worktree add -q "$WT_OTHER" -b change/task-b
SESSION=sess-worktree-guard

# A LIVE timecard: the pid and start time are this test process's own, so the card
# is live for exactly as long as the run that wrote it. `card-path` comes from the
# register itself, so this suite never re-derives the project-key hash.
card() { # $1 slug $2 worktree [$3 session] [$4 register-dir]
  local slug="$1" wt="$2" sess="${3:-$SESSION}" reg="${4:-$REGDIR}" cp key
  cp="$(AGENT_TEAM_REGISTER_DIR="$reg" bash "$REG_SH" card-path "$MAIN" "$slug")" || return 1
  mkdir -p "$(dirname "$cp")" || return 1
  key="$(basename "$(dirname "$cp")")"
  jq -n --arg slug "$slug" --arg proj "$MAIN" --arg key "$key" --arg sess "$sess" \
    --argjson pid "$$" --arg start "$(ps -p "$$" -o lstart=)" --arg wt "$wt" \
    --arg ref "refs/heads/change/$slug" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:"refs/heads/main",
      base_sha:"deadbee",state:"ready",opened:$opened,heartbeat:$hb,writer:null}' > "$cp"
}

# A subagent's OWN transcript: one dispatch prompt and zero Agent tool_use blocks,
# which is the structural test that it is not a main session's file.
own_tr() { # $1 prompt text -> path
  local path
  path="$(mktemp "$WORK/own-tr.XXXXXX")"
  jq -cn --arg p "$1" \
    '{type:"user",message:{role:"user",content:[{type:"text",text:$p}]}}' > "$path"
  printf '%s' "$path"
}

# A MAIN SESSION's transcript: dispatches, as Agent tool_use blocks. Every
# declaration in it belongs to some other agent, so this guard reads no selector
# from it at all — that is what retires the recency scan.
session_tr() { # $@ prompts -> path
  local path prompt
  path="$(mktemp "$WORK/session-tr.XXXXXX")"
  : > "$path"
  for prompt in "$@"; do
    jq -cn --arg p "$prompt" \
      '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_x",name:"Agent",input:{subagent_type:"builder",prompt:$p}}]}}' \
      >> "$path"
  done
  printf '%s' "$path"
}

write_payload() { # $1 file_path $2 transcript [$3 cwd] [$4 session]
  jq -cn --arg f "$1" --arg tr "$2" --arg cwd "${3:-$WT_MINE}" --arg sid "${4:-$SESSION}" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,session_id:$sid,
      transcript_path:$tr,tool_input:{file_path:$f,content:"x"}}'
}
edit_payload() { # $1 file_path $2 transcript [$3 cwd] [$4 session]
  jq -cn --arg f "$1" --arg tr "$2" --arg cwd "${3:-$WT_MINE}" --arg sid "${4:-$SESSION}" \
    '{hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$cwd,session_id:$sid,
      transcript_path:$tr,tool_input:{file_path:$f,old_string:"x",new_string:"y"}}'
}
bash_payload() { # $1 command $2 cwd $3 transcript [$4 session]
  jq -cn --arg c "$1" --arg cwd "$2" --arg tr "$3" --arg sid "${4:-$SESSION}" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,session_id:$sid,
      transcript_path:$tr,tool_input:{command:$c}}'
}
stop_payload() { # $1 transcript [$2 session]
  jq -cn --arg tr "$1" --arg cwd "$WT_MINE" --arg sid "${2:-$SESSION}" \
    '{hook_event_name:"SubagentStop",cwd:$cwd,session_id:$sid,transcript_path:$tr}'
}

# Three live claims for this session: the change under test, one whose recorded tree
# was never built, and one that names the shared checkout itself. With more than one
# candidate every transcript below has to select, which is the point.
card task-a "$WT_MINE" || { printf 'FAIL [fixture]: could not write the task-a timecard\n'; exit 1; }
card fake-tree "$MAIN/.claude/worktrees/never-created" || exit 1
card parent-tree "$MAIN" || exit 1
TR_MINE="$(own_tr "Implement it.
CHANGE: task-a
ACCEPTANCE CRITERIA")"
TR_FAKE="$(own_tr "Implement it.
CHANGE: fake-tree")"
TR_PARENT="$(own_tr "Implement it.
CHANGE: parent-tree")"

# --- writes inside the claimed worktree: allowed.
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_MINE")" "write inside the claimed worktree allows"
allow builder "$(edit_payload "$WT_MINE/file.txt" "$TR_MINE")" "edit inside the claimed worktree allows"
allow builder "$(write_payload "$WT_MINE/pkg/deep/mod.py" "$TR_MINE")" "write deep inside the claimed worktree allows"

# --- the separately-authored acceptance suite is read-only to whoever writes the
# code, even inside the claimed worktree — and it is NOT read-only to the agent
# whose job is authoring it. Policing the test-author out of its own bar would be a
# refusal no dispatch could ever satisfy.
block builder "$(write_payload "$WT_MINE/tests/acceptance/test_ac.py" "$TR_MINE")" \
  "write into the acceptance suite blocks"
block builder "$(edit_payload "$WT_MINE/tests/acceptance/test_ac.py" "$TR_MINE")" \
  "edit in the acceptance suite blocks"
allow builder "$(write_payload "$WT_MINE/tests/unit/test_x.py" "$TR_MINE")" \
  "write into the builder's own test dirs allows"
allow test-author "$(write_payload "$WT_MINE/tests/acceptance/test_ac.py" "$TR_MINE")" \
  "the test-author may write the acceptance suite it authors"

# --- THE REQUIREMENT: writes anywhere else are refused.
block builder "$(write_payload "$MAIN/file.txt" "$TR_MINE")" "write into the shared checkout blocks"
block builder "$(edit_payload "$MAIN/file.txt" "$TR_MINE")" "edit in the shared checkout blocks"
block builder "$(write_payload "$WT_OTHER/file.txt" "$TR_MINE")" "write into another change's worktree blocks"
block builder "$(edit_payload "$WT_OTHER/file.txt" "$TR_MINE")" "edit in another change's worktree blocks"
block builder "$(write_payload "$WORK/loose.txt" "$TR_MINE")" "write outside any worktree blocks"
# The third side of the 2026-08-04 loop: the agent memory is in no worktree, so it
# can never be the builder's. The repair is the scribe's lane reaching it (below),
# never this confinement softening.
block builder "$(write_payload "$WORK/home/.claude/projects/-p/memory/lesson.md" "$TR_MINE")" \
  "write into the agent memory blocks for a role whose lane does not reach it"

# Path trickery must not escape: a traversal that lands in the shared checkout IS
# the shared checkout, including one whose middle segment does not exist.
block builder "$(write_payload "$WT_MINE/../../../file.txt" "$TR_MINE")" "traversal out of the worktree blocks"
block builder "$(write_payload "$WT_MINE/nope/../../../file.txt" "$TR_MINE")" \
  "traversal through a missing directory still blocks"
block builder "$(write_payload "$WT_MINE/nope/../../task-b/file.txt" "$TR_MINE")" \
  "traversal through a missing directory into another worktree blocks"

# --- a claim whose recorded tree is not a registered linked worktree is not
# isolation, and the agent cannot build one itself.
block builder "$(write_payload "$MAIN/.claude/worktrees/never-created/x.py" "$TR_FAKE")" \
  "a claim whose worktree was never built blocks"
block builder "$(write_payload "$MAIN/file.txt" "$TR_PARENT")" \
  "a claim recording the shared checkout as its worktree blocks"

# --- Bash for a change-confined role: the effective working directory and every
# retargeted git must stay inside the claimed worktree.
allow builder "$(bash_payload 'pytest -q' "$WT_MINE" "$TR_MINE")" "bash run inside the claimed worktree allows"
block builder "$(bash_payload 'pytest -q' "$MAIN" "$TR_MINE")" "bash run in the shared checkout blocks"
block builder "$(bash_payload 'pytest -q' "$WT_OTHER" "$TR_MINE")" "bash run in another worktree blocks"
block builder "$(bash_payload "git -C $MAIN commit -am x" "$WT_MINE" "$TR_MINE")" "git -C into the shared checkout blocks"
block builder "$(bash_payload "git -C $WT_OTHER add ." "$WT_MINE" "$TR_MINE")" "git -C into another worktree blocks"

# THE REAL-WORLD DIRECTORY. A subagent's payload directory is its session's — fixed
# for the session's life and always the shared checkout — so judged by that alone
# every builder command was refused, including the `cd` into its own worktree: eight
# recorded refusals on 2026-08-04 from a builder whose workspace was correct.
allow builder "$(bash_payload "cd $WT_MINE; pytest -q" "$MAIN" "$TR_MINE")" \
  "a command that steps into the claimed worktree first allows"
allow builder "$(bash_payload "pushd $WT_MINE; pytest -q" "$MAIN" "$TR_MINE")" \
  "pushd into the claimed worktree allows"
allow builder "$(bash_payload "cd \"$WT_MINE\"
pytest -q" "$MAIN" "$TR_MINE")" \
  "a quoted cd on its own line allows"
allow builder "$(bash_payload "cd $WT_MINE/pkg/deep; pytest -q" "$MAIN" "$TR_MINE")" \
  "stepping into a subdirectory of the claimed worktree allows"
block builder "$(bash_payload "cd $MAIN; pytest -q" "$MAIN" "$TR_MINE")" \
  "stepping into the shared checkout still blocks"
block builder "$(bash_payload "cd $WT_OTHER; pytest -q" "$MAIN" "$TR_MINE")" \
  "stepping into another change's worktree still blocks"
block builder "$(bash_payload "cd $WT_MINE/../..; rm -rf x" "$MAIN" "$TR_MINE")" \
  "stepping out of the claimed worktree by traversal still blocks"
block builder "$(bash_payload "cd $WT_MINE; git -C $MAIN commit -am x" "$MAIN" "$TR_MINE")" \
  "stepping in and then retargeting git at the shared checkout still blocks"
block builder "$(bash_payload "echo hi; cd $WT_MINE; pytest -q" "$MAIN" "$TR_MINE")" \
  "a cd that is not the first statement is not honored"

# Writes are judged by the file path, so the payload's directory changes nothing.
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_MINE" "$MAIN")" \
  "write into the claimed worktree from the shared directory allows"
block builder "$(write_payload "$MAIN/file.txt" "$TR_MINE" "$MAIN")" \
  "write into the shared checkout from the shared directory blocks"

# Reads are never gated — and that is a property of the wiring (the guard is
# registered on Write|Edit|NotebookEdit|Bash only), so a Read that reaches this
# guard at all is simply not its business.
allow builder "$(jq -cn --arg tr "$TR_MINE" --arg cwd "$WT_MINE" --arg f "$MAIN/plan.md" --arg sid "$SESSION" \
  '{hook_event_name:"PreToolUse",tool_name:"Read",cwd:$cwd,session_id:$sid,transcript_path:$tr,tool_input:{file_path:$f}}')" \
  "a Read that reaches this guard is not gated"

# --- Stop: the backstop records, and never traps. A blocked Stop tells an agent to
# repair a workspace this same guard refuses it the tools to repair, so it can only
# loop; the register records the tree, the dispatch guard builds it before the agent
# runs, and closeout verifies it.
allow builder "$(stop_payload "$TR_MINE")" "stop with a live claim and a real tree allows"
allow builder "$(stop_payload "$TR_FAKE")" "stop whose claimed tree was never built is allowed, not trapped"

# --- other roles: the researcher and the ticketer hold no write tool at all
# (disallowedTools in their frontmatter), so this guard has nothing to police.
allow researcher "$(write_payload "$MAIN/file.txt" "$TR_MINE")" "the researcher is not policed by this guard"
allow ticketer "$(write_payload "$MAIN/file.txt" "$TR_MINE")" "the ticketer is not policed by this guard"

# --- malformed input fails closed.
block builder "not json" "malformed stdin blocks"
block builder "" "empty stdin blocks"

# --- the resolution, legality and per-role shell rules, in their own files for the
# project's file-size discipline. Sourced, so the whole suite is still one command.
# shellcheck source=tests/lib/worktree-guard-resolution-cases.sh
. "$HERE/lib/worktree-guard-resolution-cases.sh"
# shellcheck source=tests/lib/worktree-guard-shell-cases.sh
. "$HERE/lib/worktree-guard-shell-cases.sh"

# --- EVERY REFUSAL IS RECORDED, not just the confinement ones. A refusal that
# reaches only the agent's stderr cannot be counted, and on 2026-08-04 the block
# telemetry showed a builder's shell refusals while its resolution refusals left no
# trace at all — so the record answered "was it confined?" and could not answer
# "why was it stopped?".
LOG="$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl"
records() { # $1 role $2 payload $3 expected detail substring $4 label
  rm -f "$LOG"
  printf '%s' "$2" | bash "$GUARD" "$1" >/dev/null 2>&1
  local detail=""
  [ -f "$LOG" ] && detail="$(jq -r '.detail' "$LOG" | tail -n1)"
  case "$detail" in
    *"$3"*) pass "$4" ;;
    *) fail "$4" "detail '$detail' did not contain '$3'" ;;
  esac
}
records builder "$(write_payload "$MAIN/file.txt" "$TR_MINE")" \
  "$MAIN/file.txt" "a confinement refusal is recorded with its target"
records builder "$(write_payload "$MAIN/.claude/worktrees/never-created/x.py" "$TR_FAKE")" \
  "not a linked worktree" "a claim whose tree was never built is recorded"
records builder "not json" "invalid payload" "a malformed payload is recorded"
records builder "$(jq -cn --arg tr "$TR_MINE" --arg cwd "$MAIN" --arg sid "$SESSION" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,session_id:$sid,transcript_path:$tr,tool_input:{content:"x"}}')" \
  "no file path" "a Write with no file path is recorded"
records builder "$(jq -cn --arg tr "$TR_MINE" --arg sid "$SESSION" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:$sid,transcript_path:$tr,tool_input:{command:"ls"}}')" \
  "no working directory" "a Bash call with no working directory is recorded"
records builder "$(bash_payload "cd $WT_MINE; git -C $MAIN commit -am x" "$MAIN" "$TR_MINE")" \
  "$MAIN" "a git escape out of the worktree is recorded"

# A verdict must never depend on logging succeeding.
export AGENT_TEAM_TELEMETRY_DIR="/dev/null/nope"
block builder "$(write_payload "$MAIN/file.txt" "$TR_MINE")" \
  "a block still blocks when telemetry cannot be written"
allow builder "$(write_payload "$WT_MINE/ok.py" "$TR_MINE")" \
  "an allow still allows when telemetry cannot be written"
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry"

printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
