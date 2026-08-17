#!/usr/bin/env bash
# tests/test_workspace.sh — the workspace primitive: create, adopt, refuse, and
# integrate a change's worktree in one place (plan Task 3).
#
# This is the only component in the design that runs a mutating git command, so
# every rule it enforces is pinned here: an un-ignored worktree directory is
# refused, a tree registered at another ref is refused rather than moved, a stale
# registration is pruned and retried, and an integration that cannot be done
# cleanly leaves the tree, the ref, and the timecard exactly as they were.
#
# Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case, then a
# trailing `passed=<n> failed=<n>`.
#
# Safety contract: every case runs in its own throwaway git fixture with
# AGENT_TEAM_REGISTER_DIR and AGENT_TEAM_TELEMETRY_DIR inside it, so no case
# touches the machine's live register or any real checkout.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WS="$ROOT/hooks/agent-team-workspace.sh"
REG="$ROOT/hooks/agent-team-register.sh"

PASSED=0
FAILED=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/workspace-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

run_case() { # $1 label, $2 function
  local label="$1" fn="$2" why rc
  shift 2
  why="$("$fn" "$@" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf 'PASS [%s]\n' "$label"
    PASSED=$((PASSED + 1))
  else
    why="$(printf '%s' "$why" | tr '\n\t' '  ' | cut -c1-420)"
    printf 'FAIL [%s]: %s [case exit=%s]\n' "$label" "$why" "$rc"
    FAILED=$((FAILED + 1))
  fi
}

fixture() { # $1 name $2 ignore-worktrees (yes|no, default yes)
  FX="$WORK/$1"
  PROJ="$FX/proj"
  REGDIR="$FX/register"
  mkdir -p "$PROJ" "$REGDIR" || return 1
  chmod 700 "$REGDIR"
  export AGENT_TEAM_REGISTER_DIR="$REGDIR"
  export AGENT_TEAM_TELEMETRY_DIR="$FX/telemetry"
  git -C "$PROJ" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$PROJ" config user.email fixture@example.com
  git -C "$PROJ" config user.name "Workspace Fixture"
  if [ "${2:-yes}" = "yes" ]; then
    printf '.claude/worktrees/\n' > "$PROJ/.gitignore"
  else
    printf 'an-unrelated-pattern\n' > "$PROJ/.gitignore"
  fi
  printf 'base\n' > "$PROJ/file.txt"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "init: fixture project" >/dev/null 2>&1 || return 1
  PROJ="$(cd "$PROJ" && pwd -P)"
  mkdir -p "$PROJ/.claude/worktrees"
  WTPATH="$PROJ/.claude/worktrees"
}

listed_at() { # $1 worktree path $2 full ref
  git -C "$PROJ" worktree list --porcelain 2>/dev/null \
    | awk -v p="worktree $1" -v r="branch $2" '
        $0 == p {seen=1; next}
        seen && $0 == r {found=1}
        /^$/ {seen=0}
        END {exit found ? 0 : 1}'
}

ws() { bash "$WS" "$@" 2>&1; }

# --- ensure -----------------------------------------------------------------

case_ensure_creates() {
  fixture create || { printf 'fixture setup failed'; return 1; }
  local out rc
  out="$(ws ensure "$PROJ" newchange main)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ "$out" = "$WTPATH/newchange" ] \
    || { printf 'expected the derived path %s printed; observed %s' "$WTPATH/newchange" "$out"; return 1; }
  [ -d "$WTPATH/newchange" ] || { printf 'expected the worktree directory created'; return 1; }
  listed_at "$WTPATH/newchange" refs/heads/change/newchange \
    || { printf 'expected git to list the tree at refs/heads/change/newchange; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
}

case_ensure_adopts() {
  fixture adopt || { printf 'fixture setup failed'; return 1; }
  ws ensure "$PROJ" adopted main >/dev/null || { printf 'the first ensure failed'; return 1; }
  printf 'work in progress\n' > "$WTPATH/adopted/wip.txt"
  local out rc
  out="$(ws ensure "$PROJ" adopted main)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0 adopting; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ "$out" = "$WTPATH/adopted" ] || { printf 'expected the path printed; observed %s' "$out"; return 1; }
  [ -f "$WTPATH/adopted/wip.txt" ] \
    || { printf 'expected adoption to touch nothing; observed the in-progress file gone'; return 1; }
  listed_at "$WTPATH/adopted" refs/heads/change/adopted \
    || { printf 'expected the same registration after adoption'; return 1; }
}

case_ensure_refuses_other_ref() {
  fixture other-ref || { printf 'fixture setup failed'; return 1; }
  git -C "$PROJ" worktree add -q "$WTPATH/mixed" -b something-else main >/dev/null 2>&1 \
    || { printf 'could not build the fixture tree'; return 1; }
  local out rc
  out="$(ws ensure "$PROJ" mixed main)"; rc=$?
  [ "$rc" -eq 7 ] || { printf 'expected exit 7; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *something-else*) ;;
    *) printf 'expected the refusal to name the ref actually registered; observed %s' "$out"; return 1 ;;
  esac
  case "$out" in
    *"worktree remove"*) ;;
    *) printf 'expected the refusal to name its repair (worktree remove); observed %s' "$out"; return 1 ;;
  esac
  listed_at "$WTPATH/mixed" refs/heads/something-else \
    || { printf 'expected the existing registration untouched'; return 1; }
}

case_ensure_prunes_stale() {
  fixture stale || { printf 'fixture setup failed'; return 1; }
  ws ensure "$PROJ" stale main >/dev/null || { printf 'the first ensure failed'; return 1; }
  rm -rf "$WTPATH/stale"          # the registration survives; the tree does not
  local out rc
  out="$(ws ensure "$PROJ" stale main)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0 after pruning a stale registration; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ -d "$WTPATH/stale" ] || { printf 'expected the tree rebuilt at %s' "$WTPATH/stale"; return 1; }
  listed_at "$WTPATH/stale" refs/heads/change/stale \
    || { printf 'expected one clean registration; observed %s' \
         "$(git -C "$PROJ" worktree list --porcelain | tr '\n' ' ')"; return 1; }
}

case_ensure_attaches_existing_ref() {
  fixture attach || { printf 'fixture setup failed'; return 1; }
  ws ensure "$PROJ" attached main >/dev/null || { printf 'the first ensure failed'; return 1; }
  printf 'kept work\n' > "$WTPATH/attached/kept.txt"
  git -C "$WTPATH/attached" add -A >/dev/null 2>&1
  git -C "$WTPATH/attached" commit -qm "feat: work worth keeping" >/dev/null 2>&1
  local sha out rc
  sha="$(git -C "$PROJ" rev-parse refs/heads/change/attached)"
  git -C "$PROJ" worktree remove "$WTPATH/attached" >/dev/null 2>&1 \
    || { printf 'could not remove the tree for the fixture'; return 1; }
  out="$(ws ensure "$PROJ" attached main)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0 attaching to the surviving ref; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ "$(git -C "$WTPATH/attached" rev-parse HEAD)" = "$sha" ] \
    || { printf 'expected the tree back on the ref at %s; observed %s' \
         "$sha" "$(git -C "$WTPATH/attached" rev-parse HEAD 2>&1)"; return 1; }
  [ -f "$WTPATH/attached/kept.txt" ] || { printf 'expected the committed work present in the re-attached tree'; return 1; }
}

case_ensure_refuses_unignored() {
  fixture unignored no || { printf 'fixture setup failed'; return 1; }
  local out rc
  out="$(ws ensure "$PROJ" any main)"; rc=$?
  [ "$rc" -eq 7 ] || { printf 'expected exit 7 when .claude/worktrees is not ignored; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *.gitignore*) ;;
    *) printf 'expected the refusal to name the .gitignore line to add; observed %s' "$out"; return 1 ;;
  esac
  [ -d "$WTPATH/any" ] && { printf 'expected nothing created; observed a tree at %s' "$WTPATH/any"; return 1; }
  return 0
}

# --- integrate --------------------------------------------------------------

# A claimed, ready change with one commit in its own tree.
claimed_change() { # $1 slug $2 session — sets CHANGE_WT
  bash "$REG" claim "$PROJ" "$1" "$2" >/dev/null 2>&1 || return 1
  CHANGE_WT="$(ws ensure "$PROJ" "$1" main)" || return 1
  bash "$REG" ready "$PROJ" "$1" >/dev/null 2>&1 || return 1
  printf 'changed by the change\n' > "$CHANGE_WT/change.txt"
  git -C "$CHANGE_WT" add -A >/dev/null 2>&1
  git -C "$CHANGE_WT" commit -qm "feat: the change's own work" >/dev/null 2>&1
}

case_integrate_refuses_dirty() {
  fixture dirty || { printf 'fixture setup failed'; return 1; }
  claimed_change dirty sess-dirty || { printf 'fixture change failed'; return 1; }
  printf 'uncommitted\n' > "$CHANGE_WT/loose.txt"
  local out rc
  out="$(ws integrate "$PROJ" dirty main)"; rc=$?
  [ "$rc" -eq 8 ] || { printf 'expected exit 8 for a dirty change tree; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *loose.txt*) ;;
    *) printf 'expected the refusal to name the dirty path; observed %s' "$out"; return 1 ;;
  esac
  [ -f "$(bash "$REG" card-path "$PROJ" dirty)" ] \
    || { printf 'expected the timecard intact after a refusal'; return 1; }
}

case_integrate_refuses_wrong_head() {
  fixture wrong-head || { printf 'fixture setup failed'; return 1; }
  claimed_change wrong sess-wrong || { printf 'fixture change failed'; return 1; }
  local out rc
  out="$(ws integrate "$PROJ" wrong release)"; rc=$?
  [ "$rc" -eq 8 ] || { printf 'expected exit 8 when HEAD is not the integration ref; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *release*) ;;
    *) printf 'expected the refusal to name the expected integration ref; observed %s' "$out"; return 1 ;;
  esac
  listed_at "$CHANGE_WT" refs/heads/change/wrong \
    || { printf 'expected the change tree still registered after the refusal'; return 1; }
}

case_integrate_merges_and_releases() {
  fixture integrate || { printf 'fixture setup failed'; return 1; }
  claimed_change shipped sess-ship || { printf 'fixture change failed'; return 1; }
  local sha out rc card
  card="$(bash "$REG" card-path "$PROJ" shipped)"
  sha="$(git -C "$CHANGE_WT" rev-parse HEAD)"
  out="$(ws integrate "$PROJ" shipped main)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  git -C "$PROJ" merge-base --is-ancestor "$sha" HEAD \
    || { printf 'expected the change merged into main; observed HEAD=%s' "$(git -C "$PROJ" log --oneline -3 | tr '\n' ' ')"; return 1; }
  [ -d "$CHANGE_WT" ] && { printf 'expected the worktree removed; observed it still at %s' "$CHANGE_WT"; return 1; }
  git -C "$PROJ" show-ref --verify --quiet refs/heads/change/shipped \
    && { printf 'expected the change ref deleted'; return 1; }
  [ -f "$card" ] && { printf 'expected the timecard released; observed it still at %s' "$card"; return 1; }
  [ -f "$PROJ/change.txt" ] || { printf 'expected the change content in the shared checkout'; return 1; }
  return 0
}

case_conflicted_merge_aborts() {
  fixture conflict || { printf 'fixture setup failed'; return 1; }
  claimed_change clash sess-clash || { printf 'fixture change failed'; return 1; }
  # The same file, two different contents: the change's and the checkout's.
  printf 'the change wants this\n' > "$CHANGE_WT/file.txt"
  git -C "$CHANGE_WT" commit -aqm "feat: the change's version" >/dev/null 2>&1
  printf 'main wants that\n' > "$PROJ/file.txt"
  git -C "$PROJ" commit -aqm "feat: main's version" >/dev/null 2>&1
  local out rc card
  card="$(bash "$REG" card-path "$PROJ" clash)"
  out="$(ws integrate "$PROJ" clash main)"; rc=$?
  [ "$rc" -eq 8 ] || { printf 'expected exit 8 for a conflicted merge; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ -z "$(git -C "$PROJ" status --porcelain)" ] \
    || { printf 'expected the checkout clean after the abort; observed %s' "$(git -C "$PROJ" status --porcelain | tr '\n' ' ')"; return 1; }
  [ -e "$PROJ/.git/MERGE_HEAD" ] && { printf 'expected the merge aborted; observed MERGE_HEAD still present'; return 1; }
  listed_at "$CHANGE_WT" refs/heads/change/clash \
    || { printf 'expected the change tree left exactly as it was'; return 1; }
  [ -f "$card" ] || { printf 'expected the timecard left intact'; return 1; }
  return 0
}

# --- remove -----------------------------------------------------------------

case_remove_refuses_unmerged() {
  fixture remove || { printf 'fixture setup failed'; return 1; }
  claimed_change unmerged sess-rm || { printf 'fixture change failed'; return 1; }
  local out rc card
  card="$(bash "$REG" card-path "$PROJ" unmerged)"
  out="$(ws remove "$PROJ" unmerged)"; rc=$?
  [ "$rc" -eq 8 ] || { printf 'expected exit 8 for an unmerged change; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in
    *"the change's own work"* | *unmerged*) ;;
    *) printf 'expected the refusal to name the unmerged commits; observed %s' "$out"; return 1 ;;
  esac
  [ -d "$CHANGE_WT" ] || { printf 'expected the tree kept'; return 1; }
  [ -f "$card" ] || { printf 'expected the timecard kept'; return 1; }
  # Merged, the same removal is allowed.
  git -C "$PROJ" merge --no-ff --no-edit change/unmerged >/dev/null 2>&1 \
    || { printf 'could not merge the change for the second half of the case'; return 1; }
  out="$(ws remove "$PROJ" unmerged)"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'expected exit 0 removing a merged change; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  [ -d "$CHANGE_WT" ] && { printf 'expected the tree removed once merged'; return 1; }
  return 0
}

run_case 'ensure creates the derived worktree at the derived ref' case_ensure_creates
run_case 'ensure adopts an existing registered tree' case_ensure_adopts
run_case 'ensure refuses a tree registered at another ref' case_ensure_refuses_other_ref
run_case 'ensure prunes a stale registration and retries' case_ensure_prunes_stale
run_case 'ensure attaches to an existing ref whose tree was removed' case_ensure_attaches_existing_ref
run_case 'ensure refuses when the worktree directory is not gitignored' case_ensure_refuses_unignored
run_case 'integrate refuses a dirty change tree' case_integrate_refuses_dirty
run_case 'integrate refuses when HEAD is not the integration ref' case_integrate_refuses_wrong_head
run_case 'integrate merges, removes the tree, deletes the ref, and releases the card' case_integrate_merges_and_releases
run_case 'a conflicted merge aborts and leaves the claim intact' case_conflicted_merge_aborts
run_case 'remove refuses an unmerged change' case_remove_refuses_unmerged

printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
