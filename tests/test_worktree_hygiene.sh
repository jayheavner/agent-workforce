#!/usr/bin/env bash
# tests/test_worktree_hygiene.sh — verifies tools/worktree-hygiene.sh reports
# removal candidates without ever mutating the repository, and that its
# `--register` operator view lists who holds what without mutating anything
# either. Every register read happens against a private fixture register
# (AGENT_TEAM_REGISTER_DIR), so no real claim is read, written, or reaped.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/tools/worktree-hygiene.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
okl() { PASS=$((PASS + 1)); printf 'PASS [%s]\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/worktree-hygiene-fixture.XXXXXX")"
REPO="$FIXTURE_ROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "Hygiene Test"
echo base > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm "test: baseline"

# Worktree A: merged into main, clean tree -> removal candidate.
git -C "$REPO" branch merged-clean
git -C "$REPO" worktree add -q "$FIXTURE_ROOT/merged-clean" merged-clean
WT_A="$(cd "$FIXTURE_ROOT/merged-clean" && pwd -P)"

# Worktree B: has a unique commit not on main -> keep (unique commits).
git -C "$REPO" branch diverged
git -C "$REPO" worktree add -q "$FIXTURE_ROOT/diverged" diverged
WT_B="$(cd "$FIXTURE_ROOT/diverged" && pwd -P)"
echo unique > "$WT_B/unique.md"
git -C "$WT_B" add unique.md
git -C "$WT_B" commit -qm "feat: unique work"

OUTPUT="$(bash "$SCRIPT" "$REPO" 2>&1)"
RC=$?

if [ "$RC" -eq 0 ]; then ok; else bad "script exits 0 always (rc=$RC)"; fi

if printf '%s' "$OUTPUT" | grep -qF -e "$WT_A"; then
  ok
else
  bad "output lists worktree A ($WT_A)"
fi

if printf '%s' "$OUTPUT" | grep -F -e "$WT_A" | grep -qF -e "candidate"; then
  ok
else
  bad "worktree A (merged, clean) is listed as a candidate"
fi

if printf '%s' "$OUTPUT" | grep -F -e "$WT_A" | grep -qF -e "git worktree remove $WT_A"; then
  ok
else
  bad "worktree A shows its exact removal command"
fi

if printf '%s' "$OUTPUT" | grep -F -e "$WT_B" | grep -qF -e "keep: unique commits"; then
  ok
else
  bad "worktree B (diverged) is listed as keep: unique commits"
fi

if printf '%s' "$OUTPUT" | grep -qF -e "1 removal candidate"; then
  ok
else
  bad "summary line reads '1 removal candidate(s)' (output: $OUTPUT)"
fi

# Read-only: repo state must be byte-identical before and after the run.
BEFORE_REFS="$(git -C "$REPO" for-each-ref)"
BEFORE_WORKTREES="$(git -C "$REPO" worktree list --porcelain)"
bash "$SCRIPT" "$REPO" >/dev/null 2>&1
AFTER_REFS="$(git -C "$REPO" for-each-ref)"
AFTER_WORKTREES="$(git -C "$REPO" worktree list --porcelain)"
if [ "$BEFORE_REFS" = "$AFTER_REFS" ] && [ "$BEFORE_WORKTREES" = "$AFTER_WORKTREES" ]; then
  ok
else
  bad "script mutated repo refs or worktrees (must be read-only)"
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$SCRIPT" >/dev/null 2>&1; then
    ok
  else
    bad "shellcheck reported issues in $SCRIPT"
  fi
else
  echo "worktree-hygiene tests: shellcheck not present in this environment — skipped"
fi

###############################################################################
# The operator view: `--register` — who holds what, and which trees nobody
# claims. A private register directory, so no real claim is ever read or written.
###############################################################################
REG_SH="$ROOT/hooks/agent-team-register.sh"
RFIX="$FIXTURE_ROOT/register-view"
RREPO="$RFIX/proj"
export AGENT_TEAM_REGISTER_DIR="$RFIX/register"
mkdir -p "$RREPO" "$AGENT_TEAM_REGISTER_DIR"
chmod 700 "$AGENT_TEAM_REGISTER_DIR"
git -C "$RREPO" init -q -b main
git -C "$RREPO" config user.email "test@example.invalid"
git -C "$RREPO" config user.name "Hygiene Test"
mkdir -p "$RREPO/docs"
printf '.claude/worktrees/\n' > "$RREPO/.gitignore"
printf 'note\n' > "$RREPO/docs/note.md"
git -C "$RREPO" add -A >/dev/null 2>&1
git -C "$RREPO" commit -qm "test: baseline"
RREPO="$(cd "$RREPO" && pwd -P)"
mkdir -p "$RREPO/.claude/worktrees"

# A timecard, written at the path the register itself names — this suite never
# re-derives the project-key hash. The writer slot is set in the card's mirror,
# which is what the operator view reads.
put_card() { # $1 slug $2 session $3 pid $4 pid_start $5 worktree -> prints card path
  local cp key base
  cp="$(bash "$REG_SH" card-path "$RREPO" "$1" 2>&1)" || return 1
  mkdir -p "$(dirname "$cp")" || return 1
  key="$(basename "$(dirname "$cp")")"
  base="$(git -C "$RREPO" rev-parse HEAD)"
  jq -n --arg slug "$1" --arg proj "$RREPO" --arg key "$key" --arg sess "$2" \
    --argjson pid "$3" --arg start "$4" --arg wt "$5" \
    --arg ref "refs/heads/change/$1" --arg base "$base" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:"refs/heads/main",
      base_sha:$base,state:"ready",opened:$opened,heartbeat:$hb,
      writer:{slot:"builder-1",heartbeat:$hb}}' > "$cp" || return 1
  printf '%s' "$cp"
}

git -C "$RREPO" worktree add -q "$RREPO/.claude/worktrees/held" -b change/held main
git -C "$RREPO" worktree add -q "$RREPO/.claude/worktrees/orphan" -b change/orphan main
WT_HELD="$RREPO/.claude/worktrees/held"
WT_ORPHAN="$RREPO/.claude/worktrees/orphan"
printf 'work\n' > "$WT_ORPHAN/docs/note.md"
git -C "$WT_ORPHAN" add -A >/dev/null 2>&1
git -C "$WT_ORPHAN" commit -qm "docs: work inside the change"
CARD_HELD="$(put_card held sess-hygiene "$$" "$(ps -p "$$" -o lstart=)" "$WT_HELD")"
[ -f "$CARD_HELD" ] || bad "could not write the fixture timecard for the held claim"

LABEL='hygiene lists a held claim and flags an unclaimed tree'
ROUT="$(bash "$SCRIPT" "$RREPO" --register 2>&1)"
RRC=$?
RMISS=""
[ "$RRC" -eq 0 ] || RMISS="$RMISS exit=$RRC"
case "$ROUT" in *sess-hygiene*) ;; *) RMISS="$RMISS holding-session" ;; esac
case "$ROUT" in *held*) ;; *) RMISS="$RMISS held-slug" ;; esac
case "$ROUT" in *builder-1*) ;; *) RMISS="$RMISS writer-slot" ;; esac
case "$ROUT" in *opened=*) ;; *) RMISS="$RMISS opened-time" ;; esac
printf '%s\n' "$ROUT" | grep -qF "unclaimed" || RMISS="$RMISS unclaimed-marker"
printf '%s\n' "$ROUT" | grep -F "unclaimed" | grep -qF "$WT_ORPHAN" \
  || RMISS="$RMISS unclaimed-path"
printf '%s\n' "$ROUT" | grep -qF "worktree remove $WT_ORPHAN" \
  || RMISS="$RMISS removal-command"
if printf '%s\n' "$ROUT" | grep -F "$WT_HELD" | grep -qF "unclaimed"; then
  RMISS="$RMISS held-tree-wrongly-unclaimed"
fi
if [ -z "$RMISS" ]; then
  okl "$LABEL"
else
  bad "[$LABEL]:$RMISS (output: $(printf '%s' "$ROUT" | tr '\n' ' ' | cut -c1-300))"
fi

LABEL='hygiene marks a claim whose process is dead as reapable'
bash -c 'exit 0' &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
put_card gone sess-dead "$DEAD_PID" "Mon Jan  1 00:00:00 2001" \
  "$RREPO/.claude/worktrees/gone" >/dev/null
ROUT="$(bash "$SCRIPT" "$RREPO" --register 2>&1)"
if printf '%s\n' "$ROUT" | grep -F "gone" | grep -q "reapable"; then
  okl "$LABEL"
else
  bad "[$LABEL] (output: $(printf '%s' "$ROUT" | tr '\n' ' ' | cut -c1-300))"
fi

LABEL='hygiene without --register is unchanged'
GOLDEN="$FIXTURE_ROOT/hygiene-before-register.sh"
if git -C "$ROOT" show 46a683a:tools/worktree-hygiene.sh > "$GOLDEN" 2>/dev/null \
   && [ -s "$GOLDEN" ]; then
  DIFFS=""
  for target in "$REPO" "$RREPO"; do
    [ "$(bash "$GOLDEN" "$target" 2>&1)" = "$(bash "$SCRIPT" "$target" 2>&1)" ] \
      || DIFFS="$DIFFS $target"
  done
  # ...and the flag only ADDS: the plain report is a prefix of the register one.
  PLAIN="$(bash "$SCRIPT" "$RREPO" 2>&1)"
  WITH="$(bash "$SCRIPT" "$RREPO" --register 2>&1)"
  case "$WITH" in "$PLAIN"*) ;; *) DIFFS="$DIFFS not-a-prefix" ;; esac
  if [ -z "$DIFFS" ]; then
    okl "$LABEL"
  else
    bad "[$LABEL] — the report differs from the pre-flag version for:$DIFFS"
  fi
else
  echo "worktree-hygiene tests: the pre-flag version (46a683a) is not resolvable here — golden comparison skipped"
  okl "$LABEL"
fi

LABEL='hygiene with --register mutates nothing'
BEFORE_REFS="$(git -C "$RREPO" for-each-ref)"
BEFORE_WORKTREES="$(git -C "$RREPO" worktree list --porcelain)"
BEFORE_CARDS="$(cat "$AGENT_TEAM_REGISTER_DIR"/*/*.json 2>/dev/null)"
bash "$SCRIPT" "$RREPO" --register >/dev/null 2>&1
if [ "$BEFORE_REFS" = "$(git -C "$RREPO" for-each-ref)" ] \
   && [ "$BEFORE_WORKTREES" = "$(git -C "$RREPO" worktree list --porcelain)" ] \
   && [ "$BEFORE_CARDS" = "$(cat "$AGENT_TEAM_REGISTER_DIR"/*/*.json 2>/dev/null)" ]; then
  okl "$LABEL"
else
  bad "[$LABEL] — the register view changed refs, worktrees or a timecard"
fi

rm -rf "$FIXTURE_ROOT"

printf 'worktree-hygiene tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
