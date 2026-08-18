#!/usr/bin/env bash
# tests/lib/worktree-guard-shell-cases.sh — the per-role shell rule, one group per
# row of the plan's table (decision 11).
#
# Bash cannot be classified as a read or a write by looking at the tool name, so the
# rule is per ROLE, in four sets:
#   change-confined (builder, test-author) — the effective directory and every
#     retargeted git must stay inside the claimed worktree;
#   integrator (executor, deployer) — not directory-confined; a git-mutating
#     subcommand is refused outside the claimed worktree, except the one sanctioned
#     mutation of the shared checkout, agent-team-workspace.sh;
#   judge (verifier, reviewer) and diagnostic (debugger, ops) — not
#     directory-confined, so the verifier still runs the acceptance suite and the
#     reviewer still runs the plan lint from the shared checkout; every git-mutating
#     subcommand is refused, and so is an in-place file mutation whose resolvable
#     target lies inside a git working tree.
#
# The pattern lists are DEFENCE IN DEPTH, never the guarantee: an interpreter-wrapped
# write (`bash -c`, `python3 -c`), `find -delete`, or `xargs rm` reaches a file no
# pattern names. For the judge and diagnostic roles the real wall is the absence of
# Write, Edit and NotebookEdit from their frontmatter.
#
# Sourced by tests/test_worktree_guard.sh; sourcing runs the cases.

res_register shell-rules
card shell-change "$WT_MINE" "$SESSION" "$RES_REG" || fail "fixture" "could not write the shell timecard"
TR_SHELL="$(own_tr "Do the work.
CHANGE: shell-change")"

# --- change-confined: the same rule the builder has always had, now the
# test-author's too, because it writes tests inside the change like anything else.
allow test-author "$(bash_payload "cd $WT_MINE; pytest -q" "$MAIN" "$TR_SHELL")" \
  "change-confined: the test-author may run inside the claimed worktree"
block test-author "$(bash_payload 'pytest -q' "$MAIN" "$TR_SHELL")" \
  "change-confined: the test-author may not run in the shared checkout"

# --- integrator: not directory-confined, but git mutation is.
allow executor "$(bash_payload 'pytest -q' "$MAIN" "$TR_SHELL")" \
  "integrator: a non-git command in the shared checkout allows"
allow executor "$(bash_payload 'git status --short' "$MAIN" "$TR_SHELL")" \
  "integrator: a read-only git command in the shared checkout allows"
block executor "$(bash_payload "git -C $MAIN commit -am x" "$WT_MINE" "$TR_SHELL")" \
  "integrator: git -C at the shared checkout blocks"
allow executor "$(bash_payload "cd $WT_MINE; git commit -am x" "$MAIN" "$TR_SHELL")" \
  "integrator: a commit inside the claimed worktree allows"
block executor "$(bash_payload 'git commit -am x' "$MAIN" "$TR_SHELL")" \
  "integrator: a commit in the shared checkout blocks"
block deployer "$(bash_payload "git --git-dir=$MAIN/.git --work-tree=$MAIN reset --hard" "$WT_MINE" "$TR_SHELL")" \
  "integrator: --git-dir aimed at the shared checkout blocks"
block executor "$(bash_payload 'git --no-pager commit -am x' "$MAIN" "$TR_SHELL")" \
  "integrator: a leading global option does not hide the subcommand"
# The one head-ref subcommand this project bans in prose is required in the matched
# set: without it, `git <that subcommand> -D change/<slug>` destroys a change's ref
# and its history undetected, which is the loss this whole plan exists to prevent.
block executor "$(bash_payload 'git branch -D change/shell-change' "$MAIN" "$TR_SHELL")" \
  "integrator: deleting a change's own ref from the shared checkout blocks"
# The one sanctioned mutation of the shared checkout: closeout needs it.
allow executor "$(bash_payload "bash $WS_SH integrate $MAIN shell-change" "$MAIN" "$TR_SHELL")" \
  "integrator: the sanctioned workspace command may mutate the shared checkout"
allow executor "$(bash_payload "bash $WS_SH remove $MAIN shell-change" "$MAIN" "$TR_SHELL")" \
  "integrator: the sanctioned workspace removal is allowed too"

# --- judge and diagnostic: reads run anywhere, mutation runs nowhere.
allow verifier "$(bash_payload 'bash tests/acceptance/test_workspace_isolation.sh' "$MAIN" "$TR_SHELL")" \
  "judge: the verifier runs the acceptance suite from the shared checkout"
allow reviewer "$(bash_payload 'python3 tools/lint_acceptance_checks.py plans/p.md' "$MAIN" "$TR_SHELL")" \
  "judge: the reviewer runs the plan lint from the shared checkout"
allow verifier "$(bash_payload 'git log --oneline -3' "$MAIN" "$TR_SHELL")" \
  "judge: a read-only git command allows"
block verifier "$(bash_payload "git -C $MAIN commit -am wip" "$MAIN" "$TR_SHELL")" \
  "judge: a git-mutating command in the shared checkout blocks"
block verifier "$(bash_payload "cd $WT_MINE; git commit -am wip" "$MAIN" "$TR_SHELL")" \
  "judge: a git-mutating command blocks even inside the claimed worktree"
block reviewer "$(bash_payload "sed -i '' s/note/other/ $MAIN/docs/note.md" "$MAIN" "$TR_SHELL")" \
  "judge: an in-place edit of a file inside a working tree blocks"
allow reviewer "$(bash_payload "sed -i '' s/a/b/ $WORK/scratch.txt" "$MAIN" "$TR_SHELL")" \
  "judge: the same edit outside every working tree allows"
block debugger "$(bash_payload "printf x > $MAIN/file.txt" "$MAIN" "$TR_SHELL")" \
  "diagnostic: a redirection into a working tree blocks"
allow debugger "$(bash_payload "printf x > $WORK/out.txt" "$MAIN" "$TR_SHELL")" \
  "diagnostic: a redirection outside every working tree allows"
allow ops "$(bash_payload "mkdir -p $WORK/scratch/deep" "$MAIN" "$TR_SHELL")" \
  "diagnostic: scratch directories outside every working tree allow"
block ops "$(bash_payload "rm -rf $MAIN/docs" "$MAIN" "$TR_SHELL")" \
  "diagnostic: removing a directory inside a working tree blocks"
allow ops "$(bash_payload 'pytest -q 2>&1 | tail -n5' "$MAIN" "$TR_SHELL")" \
  "diagnostic: a stderr redirection is not a file target"
# The classification fails CLOSED for these two sets: a git invocation whose
# subcommand cannot be identified at all is refused rather than allowed.
block verifier "$(bash_payload 'git --exec-path=/opt/git-core' "$MAIN" "$TR_SHELL")" \
  "judge: a git command with no identifiable subcommand blocks"
allow verifier "$(bash_payload 'git --version' "$MAIN" "$TR_SHELL")" \
  "judge: git --version is identified and allowed"

# --- roles that hold no shell at all. The architect and the scribe write documents
# through Write and Edit; their frontmatter grants no Bash, so a Bash payload from
# either is refused rather than classified into a set that was never written for it.
block architect "$(bash_payload 'ls -la' "$MAIN" "$TR_SHELL")" \
  "a role whose frontmatter grants no Bash is refused a shell command"
block scribe "$(bash_payload 'ls -la' "$MAIN" "$TR_SHELL")" \
  "the same for the scribe"

# --- a change-confined role with no claim cannot be confined, so it cannot run —
# unless its dispatch asserted it writes nothing, which the dispatch guard accepts
# in place of a change. Then the judge rule applies instead of a directory.
res_register shell-no-claim
TR_BARE="$(own_tr "Do the work. No change is declared.")"
TR_BARE_SAFE="$(own_tr "Do the work.
PARALLEL_SAFE: this dispatch writes nothing")"
block_naming builder "$(bash_payload 'pytest -q' "$MAIN" "$TR_BARE")" \
  "change-confined: a shell command with no claim at all is refused" \
  "CHANGE:"
allow builder "$(bash_payload 'pytest -q' "$MAIN" "$TR_BARE_SAFE")" \
  "a PARALLEL_SAFE dispatch may still run a read-only command"
block builder "$(bash_payload 'git commit -am x' "$MAIN" "$TR_BARE_SAFE")" \
  "a PARALLEL_SAFE dispatch may not run a git-mutating command"

export AGENT_TEAM_REGISTER_DIR="$REGDIR"
