#!/usr/bin/env bash
# tests/test_worktree_guard.sh — verifies the builder worktree guard: a builder
# may only WRITE inside its own linked git worktree, and may not finish unless
# it worked in one. Reads outside the worktree stay legal (the plan, repo
# guidance, and CONTEXT.md all live in the parent checkout).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-worktree-guard.sh"
PASS=0
FAIL=0

expect() { # $1 expected_rc $2 role $3 json $4 label
  set +e
  printf '%s' "$3" | bash "$GUARD" "$2" >/dev/null 2>&1
  local rc=$?
  set -u
  if [ "$rc" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$4]: expected=$1 got=$rc"
  fi
}
allow() { expect 0 "$1" "$2" "$3"; }
block() { expect 2 "$1" "$2" "$3"; }

# --- real fixture: a main checkout plus two linked worktrees.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/worktree-guard.XXXXXX")"
MAIN="$WORK/main"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@example.com
git -C "$MAIN" config user.name Test
printf 'x\n' > "$MAIN/file.txt"
git -C "$MAIN" add file.txt
git -C "$MAIN" commit -qm init
mkdir -p "$MAIN/.claude/worktrees"
WT_MINE="$MAIN/.claude/worktrees/task-a-b1"
WT_OTHER="$MAIN/.claude/worktrees/task-b-b2"
git -C "$MAIN" worktree add -q "$WT_MINE" -b task-a
git -C "$MAIN" worktree add -q "$WT_OTHER" -b task-b

# A subagent transcript whose dispatch prompt declares $1 as the worktree.
declared_transcript() { # $1 worktree -> path
  local path
  path="$(mktemp "${TMPDIR:-/tmp}/worktree-guard-tr.XXXXXX")"
  jq -cn --arg p "Implement it.
WORKTREE: $1
ACCEPTANCE CRITERIA" \
    '{type:"user",message:{role:"user",content:[{type:"text",text:$p}]}}' > "$path"
  printf '%s' "$path"
}
UNDECLARED_TRANSCRIPT="$(mktemp "${TMPDIR:-/tmp}/worktree-guard-tr.XXXXXX")"
jq -cn '{type:"user",message:{role:"user",content:[{type:"text",text:"Implement it. No worktree named."}]}}' \
  > "$UNDECLARED_TRANSCRIPT"
TR_MINE="$(declared_transcript "$WT_MINE")"

write_payload() { # $1 file_path $2 transcript
  jq -cn --arg f "$1" --arg tr "$2" --arg cwd "$WT_MINE" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,transcript_path:$tr,tool_input:{file_path:$f,content:"x"}}'
}
edit_payload() { # $1 file_path $2 transcript
  jq -cn --arg f "$1" --arg tr "$2" --arg cwd "$WT_MINE" \
    '{hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$cwd,transcript_path:$tr,tool_input:{file_path:$f,old_string:"x",new_string:"y"}}'
}
bash_payload() { # $1 command $2 cwd $3 transcript
  jq -cn --arg c "$1" --arg cwd "$2" --arg tr "$3" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,transcript_path:$tr,tool_input:{command:$c}}'
}
stop_payload() { # $1 transcript
  jq -cn --arg tr "$1" --arg cwd "$WT_MINE" \
    '{hook_event_name:"SubagentStop",cwd:$cwd,transcript_path:$tr}'
}

# --- writes inside the builder's own declared worktree: allowed.
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_MINE")" "write inside own worktree allows"
allow builder "$(edit_payload "$WT_MINE/file.txt" "$TR_MINE")" "edit inside own worktree allows"
allow builder "$(write_payload "$WT_MINE/pkg/deep/mod.py" "$TR_MINE")" "write deep inside own worktree allows"

# --- the separately-authored acceptance suite is read-only to the builder, even
# inside its own worktree: whoever writes the code is never the last author of
# the bar it is judged against. Prose in builder.md until 2026-08-03; enforced
# here after an executor authored a change and its own test in one actor.
block builder "$(write_payload "$WT_MINE/tests/acceptance/test_ac.py" "$TR_MINE")" \
  "write into the acceptance suite blocks"
block builder "$(edit_payload "$WT_MINE/tests/acceptance/test_ac.py" "$TR_MINE")" \
  "edit in the acceptance suite blocks"
allow builder "$(write_payload "$WT_MINE/tests/unit/test_x.py" "$TR_MINE")" \
  "write into the builder's own test dirs allows"

# --- THE REQUIREMENT: writes anywhere else are refused.
block builder "$(write_payload "$MAIN/file.txt" "$TR_MINE")" "write into the parent checkout blocks"
block builder "$(edit_payload "$MAIN/file.txt" "$TR_MINE")" "edit in the parent checkout blocks"
block builder "$(write_payload "$WT_OTHER/file.txt" "$TR_MINE")" "write into ANOTHER builder's worktree blocks"
block builder "$(edit_payload "$WT_OTHER/file.txt" "$TR_MINE")" "edit in another builder's worktree blocks"
block builder "$(write_payload "$WORK/loose.txt" "$TR_MINE")" "write outside any worktree blocks"

# Path trickery must not escape: a traversal that lands in the parent checkout
# is the parent checkout.
block builder "$(write_payload "$WT_MINE/../../../file.txt" "$TR_MINE")" "traversal out of the worktree blocks"
# A traversal whose MIDDLE segment does not exist cannot be resolved by walking
# existing ancestors, so before 2026-08-03 it kept the worktree prefix and was
# accepted as inside. Normalization now happens textually first.
block builder "$(write_payload "$WT_MINE/nope/../../../file.txt" "$TR_MINE")" \
  "traversal through a missing directory still blocks"
block builder "$(write_payload "$WT_MINE/nope/../../task-b-b2/file.txt" "$TR_MINE")" \
  "traversal through a missing directory into another worktree blocks"

# --- Bash: the working directory must be the builder's worktree, and an
# explicit -C outside it is a write it does not own.
allow builder "$(bash_payload 'pytest -q' "$WT_MINE" "$TR_MINE")" "bash run inside own worktree allows"
block builder "$(bash_payload 'pytest -q' "$MAIN" "$TR_MINE")" "bash run in the parent checkout blocks"
block builder "$(bash_payload 'pytest -q' "$WT_OTHER" "$TR_MINE")" "bash run in another worktree blocks"
block builder "$(bash_payload "git -C $MAIN commit -am x" "$WT_MINE" "$TR_MINE")" "git -C into the parent checkout blocks"
block builder "$(bash_payload "git -C $WT_OTHER add ." "$WT_MINE" "$TR_MINE")" "git -C into another worktree blocks"

# --- THE REAL-WORLD DIRECTORY. Every case above hands the guard a working
# directory the builder never actually has: a subagent's directory is its
# session's, fixed for the session's life, and always the parent checkout. Judged
# by that alone the guard refused a builder EVERY shell command it ran, including
# the `cd` into its own worktree — eight recorded refusals on 2026-08-04, each
# naming the parent checkout, from a builder whose worktree was correct. The
# effective directory is therefore the declared worktree when the command opens by
# stepping into it, and the payload's directory otherwise.
allow builder "$(bash_payload "cd $WT_MINE; pytest -q" "$MAIN" "$TR_MINE")" \
  "a command that steps into its own worktree first allows"
allow builder "$(bash_payload "pushd $WT_MINE; pytest -q" "$MAIN" "$TR_MINE")" \
  "pushd into its own worktree allows"
allow builder "$(bash_payload "cd \"$WT_MINE\"
pytest -q" "$MAIN" "$TR_MINE")" \
  "a quoted cd on its own line allows"
allow builder "$(bash_payload "cd $WT_MINE/pkg/deep; pytest -q" "$MAIN" "$TR_MINE")" \
  "stepping into a subdirectory of its own worktree allows"
# Honoring that first step must widen nothing else.
block builder "$(bash_payload "cd $MAIN; pytest -q" "$MAIN" "$TR_MINE")" \
  "stepping into the parent checkout still blocks"
block builder "$(bash_payload "cd $WT_OTHER; pytest -q" "$MAIN" "$TR_MINE")" \
  "stepping into another builder's worktree still blocks"
block builder "$(bash_payload "cd $WT_MINE/../..; rm -rf x" "$MAIN" "$TR_MINE")" \
  "stepping out of its own worktree by traversal still blocks"
block builder "$(bash_payload "cd $WT_MINE; git -C $MAIN commit -am x" "$MAIN" "$TR_MINE")" \
  "stepping in and then retargeting git at the parent checkout still blocks"
block builder "$(bash_payload "echo hi; cd $WT_MINE; pytest -q" "$MAIN" "$TR_MINE")" \
  "a cd that is not the first statement is not honored"
# Writes are judged by the file path, so the same real-world directory changes
# nothing about them — stated as a test so it cannot regress silently.
allow builder "$(jq -cn --arg f "$WT_MINE/new.py" --arg tr "$TR_MINE" --arg cwd "$MAIN" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,transcript_path:$tr,tool_input:{file_path:$f,content:"x"}}')" \
  "write into own worktree from the parent directory allows"
block builder "$(jq -cn --arg f "$MAIN/file.txt" --arg tr "$TR_MINE" --arg cwd "$MAIN" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,transcript_path:$tr,tool_input:{file_path:$f,content:"x"}}')" \
  "write into the parent checkout from the parent directory blocks"

# Reading the plan in the parent checkout stays legal — the builder needs it.
allow builder "$(jq -cn --arg tr "$TR_MINE" --arg cwd "$WT_MINE" --arg f "$MAIN/plan.md" \
  '{hook_event_name:"PreToolUse",tool_name:"Read",cwd:$cwd,transcript_path:$tr,tool_input:{file_path:$f}}')" \
  "Read outside the worktree allows"

# --- fail closed: a builder with no declared worktree cannot write at all.
block builder "$(write_payload "$WT_MINE/new.py" "$UNDECLARED_TRANSCRIPT")" \
  "undeclared worktree blocks even a plausible write"

# --- a declared path that is not a real linked worktree is not isolation.
TR_FAKE="$(declared_transcript "$MAIN/.claude/worktrees/never-created")"
block builder "$(write_payload "$MAIN/.claude/worktrees/never-created/x.py" "$TR_FAKE")" \
  "declared path that is not a registered worktree blocks"

# --- the declared worktree may never be the parent checkout.
TR_PARENT="$(declared_transcript "$MAIN")"
block builder "$(write_payload "$MAIN/file.txt" "$TR_PARENT")" \
  "declaring the parent checkout as the worktree blocks"

# --- Stop: a builder cannot finish unless it worked in a real linked worktree.
allow builder "$(stop_payload "$TR_MINE")" "stop with a real declared worktree allows"
block builder "$(stop_payload "$UNDECLARED_TRANSCRIPT")" "stop with no declared worktree blocks"
block builder "$(stop_payload "$TR_FAKE")" "stop with an unregistered worktree blocks"
block builder "$(stop_payload "$TR_PARENT")" "stop declaring the parent checkout blocks"

# --- other roles are not policed by this guard.
allow verifier "$(write_payload "$MAIN/file.txt" "$TR_MINE")" "non-builder role passes through"
allow executor "$(bash_payload 'git commit -am x' "$MAIN" "$TR_MINE")" "executor in the checkout passes through"

# --- malformed input fails closed.
block builder "not json" "malformed stdin blocks"
block builder "" "empty stdin blocks"

# --- WHICH DECLARATION IS THIS BUILDER'S. The transcript a hook is handed is not
# always the subagent's own; a main-session transcript accumulates every dispatch of
# the session and is append-only. Reading the FIRST marker line there means reading
# the OLDEST declaration in the session, forever. On 2026-08-04 one session's first
# builder was dispatched with a malformed path, and every later builder inherited it
# — six correct dispatches refused by a line written ninety minutes earlier, and no
# possible dispatch could have fixed it. The declaration is this builder's dispatch,
# not the first text in a shared file that happens to match.
dispatch_entry() { # $1 id $2 role $3 worktree (empty = no declaration) -> jsonl line
  local prompt="Implement it."
  [ -n "$3" ] && prompt="Implement it.
WORKTREE: $3"
  jq -cn --arg id "$1" --arg role "$2" --arg p "$prompt" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:$role,prompt:$p}}]}}'
}
result_entry() { # $1 id $2 text
  jq -cn --arg id "$1" --arg t "$2" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:$t}]}]}}'
}
session_transcript() { # $@ jsonl lines -> path
  local path; path="$(mktemp "${TMPDIR:-/tmp}/worktree-guard-session.XXXXXX")"
  printf '%s\n' "$@" > "$path"
  printf '%s' "$path"
}

# THE REGRESSION, in the shape that produced it: an old resolved dispatch naming a
# path that is malformed and gone, then the live dispatch naming this worktree.
TR_POISONED="$(session_transcript \
  "$(dispatch_entry toolu_old builder "$MAIN/deleted-tree (already created by an earlier dispatch; branch fix/x)")" \
  "$(result_entry toolu_old 'blocked')" \
  "$(dispatch_entry toolu_live builder "$WT_MINE")")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_POISONED")" \
  "the live dispatch's declaration wins over an older resolved one"
allow builder "$(bash_payload "cd $WT_MINE; pytest -q" "$MAIN" "$TR_POISONED")" \
  "the same, for a shell command"
block builder "$(write_payload "$MAIN/file.txt" "$TR_POISONED")" \
  "and the live declaration still confines the write"

# A dispatch that has resolved is not this builder; a later live one is.
TR_TWO_LIVE="$(session_transcript \
  "$(dispatch_entry toolu_a builder "$WT_OTHER")" \
  "$(result_entry toolu_a 'done')" \
  "$(dispatch_entry toolu_b builder "$WT_MINE")")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_TWO_LIVE")" \
  "a resolved dispatch does not govern the builder that is still running"

# A launch stub is not a result: a background dispatch is still live.
TR_BACKGROUND="$(session_transcript \
  "$(dispatch_entry toolu_bg builder "$WT_MINE")" \
  "$(result_entry toolu_bg 'Async agent launched successfully')" \
  "$(dispatch_entry toolu_later builder "$WT_OTHER")" \
  "$(result_entry toolu_later 'done')")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_BACKGROUND")" \
  "a background launch stub does not resolve its dispatch"

# Only builder dispatches declare a builder's worktree.
TR_OTHER_ROLE="$(session_transcript \
  "$(dispatch_entry toolu_x executor "$WT_OTHER")" \
  "$(dispatch_entry toolu_y builder "$WT_MINE")")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_OTHER_ROLE")" \
  "another role's declaration is not the builder's"

# When every dispatch has resolved, the most recent one is still the best answer.
TR_ALL_DONE="$(session_transcript \
  "$(dispatch_entry toolu_1 builder "$WT_OTHER")" \
  "$(result_entry toolu_1 'done')" \
  "$(dispatch_entry toolu_2 builder "$WT_MINE")" \
  "$(result_entry toolu_2 'done')")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_ALL_DONE")" \
  "with nothing live, the most recent declaration governs"

# A subagent's own transcript has no dispatch blocks at all — the text scan is the
# fallback, and it must keep working.
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_MINE")" \
  "a subagent's own transcript still resolves its dispatch prompt"

# Two builders live at once is a genuine ambiguity this guard resolves by recency.
# It must be recorded, because a wrong pick aims a builder at a peer's tree.
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry-ambiguous"
TR_AMBIGUOUS="$(session_transcript \
  "$(dispatch_entry toolu_p builder "$WT_OTHER")" \
  "$(dispatch_entry toolu_q builder "$WT_MINE")")"
printf '%s' "$(write_payload "$WT_MINE/new.py" "$TR_AMBIGUOUS")" | bash "$GUARD" builder >/dev/null 2>&1
AMB_LOG="$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl"
if [ -f "$AMB_LOG" ] && [ "$(jq -r 'select(.verdict == "ambiguous") | .detail' "$AMB_LOG" | wc -l | tr -d ' ')" -gt 0 ]; then
  PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [two live declarations are recorded as ambiguous]"; fi
unset AGENT_TEAM_TELEMETRY_DIR
rm -f "$TR_POISONED" "$TR_TWO_LIVE" "$TR_BACKGROUND" "$TR_OTHER_ROLE" "$TR_ALL_DONE" "$TR_AMBIGUOUS"

# --- EVERY REFUSAL IS RECORDED, not just the confinement ones. A refusal that
# reaches only the agent's stderr cannot be counted, and on 2026-08-04 the block
# telemetry showed a builder's shell refusals while its declaration and payload
# refusals left no trace at all — so the record answered "was it confined?" and
# could not answer "why was it stopped?". Each reason carries its own detail.
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry"
LOG="$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl"
records() { # $1 role $2 json $3 expected detail substring $4 label
  rm -f "$LOG"
  printf '%s' "$2" | bash "$GUARD" "$1" >/dev/null 2>&1
  local detail=""
  [ -f "$LOG" ] && detail="$(jq -r '.detail' "$LOG" | tail -n1)"
  case "$detail" in
    *"$3"*) PASS=$((PASS+1)) ;;
    *) FAIL=$((FAIL+1)); echo "FAIL [$4]: detail='$detail' did not contain '$3'" ;;
  esac
}
records builder "$(write_payload "$WT_MINE/new.py" "$UNDECLARED_TRANSCRIPT")" \
  "no worktree declared" "an undeclared worktree is recorded"
records builder "$(write_payload "$MAIN/.claude/worktrees/never-created/x.py" "$TR_FAKE")" \
  "not a linked worktree" "a declared path that is not a worktree is recorded"
records builder "not json" "invalid payload" "a malformed payload is recorded"
records builder "$(jq -cn --arg tr "$TR_MINE" --arg cwd "$MAIN" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,transcript_path:$tr,tool_input:{content:"x"}}')" \
  "no file path" "a Write with no file path is recorded"
records builder "$(jq -cn --arg tr "$TR_MINE" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",transcript_path:$tr,tool_input:{command:"ls"}}')" \
  "no working directory" "a Bash call with no working directory is recorded"
records builder "$(bash_payload "cd $WT_MINE; git -C $MAIN commit -am x" "$MAIN" "$TR_MINE")" \
  "git -C" "a git -C escape is recorded"
# A verdict must never depend on logging succeeding.
export AGENT_TEAM_TELEMETRY_DIR="/dev/null/nope"
block builder "$(write_payload "$MAIN/file.txt" "$TR_MINE")" \
  "a block still blocks when telemetry cannot be written"
allow builder "$(write_payload "$WT_MINE/ok.py" "$TR_MINE")" \
  "an allow still allows when telemetry cannot be written"
unset AGENT_TEAM_TELEMETRY_DIR

rm -rf "$WORK"
rm -f "$TR_MINE" "$TR_FAKE" "$TR_PARENT" "$UNDECLARED_TRANSCRIPT"

echo "worktree-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
