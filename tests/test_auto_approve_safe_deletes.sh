#!/usr/bin/env bash
# tests/test_auto_approve_safe_deletes.sh — the PreToolUse(Bash) delete guard
# (tools/auto-approve-safe-deletes.py) allows rm only inside session-temp
# territory and abstains on everything it cannot positively verify.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../tools/auto-approve-safe-deletes.py"
WORK="$(mktemp -d /private/tmp/deltest.XXXXXX)"              # matches no safe pattern
SAFE="/private/tmp/claude-000/session/scratchpad"            # matches claude-* pattern
trap 'rm -rf "$WORK" /private/tmp/claude-000' EXIT
mkdir -p "$SAFE/deltest"
touch "$SAFE/deltest/a.tmp" "$SAFE/deltest/b.tmp" "$SAFE/deltest/a b.tmp"
ln -sfn /usr/bin "$SAFE/deltest/escape-link"   # symlink whose realpath leaves safe territory

# Real main checkout + linked worktree (worktree targets are safe; main is not).
REPO="$WORK/mainrepo"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$WORK/wt" >/dev/null 2>&1
touch "$WORK/wt/inside.txt" "$REPO/tracked.txt"
ln -sfn /usr/bin "$WORK/wt/escape-link"
mkdir -p "$WORK/fakewt"
printf 'gitdir: /somewhere/unrelated\n' > "$WORK/fakewt/.git"   # forged pointer, wrong shape
touch "$WORK/fakewt/f.txt"

PASS=0
FAIL=0
run_case() { # $1 desc, $2 expected(allow|abstain), $3 command, $4 cwd
  local out got
  out="$(python3 - "$3" "${4:-/Users/jay}" <<'PY' | python3 "$HOOK"
import json, sys
print(json.dumps({"tool_name": "Bash", "cwd": sys.argv[2],
                  "tool_input": {"command": sys.argv[1]}}))
PY
)"
  if [ -n "$out" ]; then got=allow; else got=abstain; fi
  if [ "$got" = "$2" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: %s (want %s, got %s)\n' "$1" "$2" "$got"
  fi
}

run_case "safe absolute file"        allow   "rm -f $SAFE/deltest/a.tmp"
run_case "safe glob"                 allow   "rm -rf $SAFE/deltest/*.tmp"
run_case "quoted path with space"    allow   "rm -f '$SAFE/deltest/a b.tmp'"
run_case "relative target, safe cwd" allow   "rm b.tmp" "$SAFE/deltest"
run_case "macOS per-user temp"       allow   "rm -rf /private/var/folders/ab/cdef/T/somefile"
run_case "TMPDIR spelling (/var)"    allow   "rm -rf /var/folders/ab/cdef/T/somefile"
run_case "unresolved /tmp spelling"  allow   "rm -f /tmp/claude-000/session/scratchpad/deltest/b.tmp"
run_case "/var outside T"            abstain "rm -rf /var/log/somefile"
run_case "workforce backups"         allow   "rm -rf $HOME/.claude/backups/agent-team-20260718"
run_case "home path"                 abstain "rm -rf $HOME/Documents/x"
run_case "project path"              abstain "rm -rf $HERE/../README.md"
run_case "compound command"          abstain "rm $SAFE/deltest/a.tmp && echo more"
run_case "dotdot escape"             abstain "rm -rf $SAFE/deltest/../../../../etc/foo"
run_case "glob-then-dotdot escape"   abstain "rm -rf $SAFE/deltest/*/../.."
run_case "symlink escape"            abstain "rm -r $SAFE/deltest/escape-link"
run_case "unexpanded variable"       abstain 'rm -rf $TMPDIR/foo'
run_case "not rm"                    abstain "rmdir $SAFE/deltest"
run_case "whole uid root"            abstain "rm -rf /private/tmp/claude-000"
run_case "flags but no target"       abstain "rm -rf"
run_case "relative target, unsafe cwd" abstain "rm a.tmp" "$WORK"
run_case "file in linked worktree"   allow   "rm $WORK/wt/inside.txt"
run_case "worktree root itself"      allow   "rm -rf $WORK/wt"
run_case "relative target, worktree cwd" allow "rm inside.txt" "$WORK/wt"
run_case "glob in linked worktree"   allow   "rm -f $WORK/wt/*.txt"
run_case "file in MAIN checkout"     abstain "rm $REPO/tracked.txt"
run_case "worktree cwd, outside target" abstain "rm -rf /Users/jay/Documents/x" "$WORK/wt"
run_case "forged .git pointer"       abstain "rm $WORK/fakewt/f.txt"
run_case "worktree symlink escape"   abstain "rm -r $WORK/wt/escape-link"

# Git deletions of task-created objects (2026-07-22: the innovation-awards
# session prompted on every worktree/branch cleanup — deletions of things the
# team itself created). Same posture: allow only what is provably safe, git's
# own refusals (dirty worktree, unmerged branch) as the second net.
run_case "git worktree remove (linked)"  allow   "git worktree remove $WORK/wt"
run_case "git worktree remove --force"   abstain "git worktree remove --force $WORK/wt"
run_case "git worktree remove main repo" abstain "git worktree remove $REPO"
run_case "git worktree prune"            allow   "git worktree prune"
run_case "git branch -d"                 allow   "git branch -d feature-x"
run_case "git branch --delete"           allow   "git branch --delete feature-x"
run_case "git branch -d multiple"        allow   "git branch -d feature-x feature-y"
run_case "git branch -D"                 abstain "git branch -D feature-x"
run_case "git branch -d -f"              abstain "git branch -d -f feature-x"
run_case "git branch -d -r (remote)"     abstain "git branch -d -r origin/feature-x"
run_case "git push --delete"             abstain "git push origin --delete feature-x"
run_case "git -C indirection"            abstain "git -C $WORK/mainrepo worktree remove $WORK/wt"
run_case "git branch (list, no delete)"  abstain "git branch"

# A non-Bash tool payload must be ignored entirely.
NONBASH="$(python3 - "$SAFE/deltest/a.tmp" <<'PY' | python3 "$HOOK"
import json, sys
print(json.dumps({"tool_name": "Write", "cwd": "/Users/jay",
                  "tool_input": {"command": "rm -f " + sys.argv[1]}}))
PY
)"
if [ -z "$NONBASH" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: non-Bash tool ignored"; fi

# Allow decision must be well-formed JSON naming the PreToolUse event.
DECISION="$(python3 - "$SAFE/deltest/a.tmp" <<'PY' | python3 "$HOOK"
import json, sys
print(json.dumps({"tool_name": "Bash", "cwd": "/Users/jay",
                  "tool_input": {"command": "rm -f " + sys.argv[1]}}))
PY
)"
if printf '%s' "$DECISION" | python3 -c '
import json, sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "PreToolUse" and d["permissionDecision"] == "allow"
' 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: allow decision JSON shape"; fi

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
