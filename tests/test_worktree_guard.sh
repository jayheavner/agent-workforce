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

# --- THE REQUIREMENT: writes anywhere else are refused.
block builder "$(write_payload "$MAIN/file.txt" "$TR_MINE")" "write into the parent checkout blocks"
block builder "$(edit_payload "$MAIN/file.txt" "$TR_MINE")" "edit in the parent checkout blocks"
block builder "$(write_payload "$WT_OTHER/file.txt" "$TR_MINE")" "write into ANOTHER builder's worktree blocks"
block builder "$(edit_payload "$WT_OTHER/file.txt" "$TR_MINE")" "edit in another builder's worktree blocks"
block builder "$(write_payload "$WORK/loose.txt" "$TR_MINE")" "write outside any worktree blocks"

# Path trickery must not escape: a traversal that lands in the parent checkout
# is the parent checkout.
block builder "$(write_payload "$WT_MINE/../../../file.txt" "$TR_MINE")" "traversal out of the worktree blocks"

# --- Bash: the working directory must be the builder's worktree, and an
# explicit -C outside it is a write it does not own.
allow builder "$(bash_payload 'pytest -q' "$WT_MINE" "$TR_MINE")" "bash run inside own worktree allows"
block builder "$(bash_payload 'pytest -q' "$MAIN" "$TR_MINE")" "bash run in the parent checkout blocks"
block builder "$(bash_payload 'pytest -q' "$WT_OTHER" "$TR_MINE")" "bash run in another worktree blocks"
block builder "$(bash_payload "git -C $MAIN commit -am x" "$WT_MINE" "$TR_MINE")" "git -C into the parent checkout blocks"
block builder "$(bash_payload "git -C $WT_OTHER add ." "$WT_MINE" "$TR_MINE")" "git -C into another worktree blocks"

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

rm -rf "$WORK"
rm -f "$TR_MINE" "$TR_FAKE" "$TR_PARENT" "$UNDECLARED_TRANSCRIPT"

echo "worktree-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
