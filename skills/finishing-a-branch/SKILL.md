---
name: finishing-a-branch
description: Take completed branch work from "code done" to integrated and cleaned up — fresh verification gate, atomic commit of only this work, integration path chosen by the human, post-merge cleanup. Use when implementation is complete and the work needs committing, merging, or a PR; when asked to "wrap up", "ship", "land", or "finish" a branch; or before offering work for integration.
requires: [verifying, reviewing]
---

# Finishing a Branch

Job: move finished work from a branch into the codebase without losing
changes, sweeping in unrelated ones, or integrating anything unverified.
"Done coding" and "integrated" are different states; this skill is the
path between them.

## The finish gate

Before any commit is finalized or integration offered:

- Run the work's stated acceptance criteria — or the full test suite when
  no criteria exist — fresh, after the last edit, per `verifying`. The
  feature's own tests passing is not the gate; the *suite* is. A sibling
  test the change broke is this work's bug.
- Red means stop: fix it here if the cause is this branch's change, and
  re-run the gate; report it as blocking if it isn't. Nothing merges,
  pushes, or becomes a PR while the gate is red.
- Read the full diff against the base branch per `reviewing` before
  offering the work for integration.

## Committing only this work

Start from `git status`, not from `git add -A`. Stage the hunks that
belong to this work; anything else in the tree is surfaced to the human —
left uncommitted, stashed with a note, or offered as a separate commit —
never swept into the feature commit and never silently discarded.

Resolve `policy:git-conventions` from the project policy and state the
resolved value and its source — project policy / user policy / judgment
default — before writing the commit message. Where no policy defines it:
atomic commits scoped to one change, imperative subject, body says why.

## The integration decision

Integration is the human's call, not an inference from "done" or "wrap it
up." Present the real options with a recommendation grounded in the repo:

1. Merge into the base branch locally.
2. Push and open a PR (only if a remote exists; note the repo's observed
   merge/PR conventions from its history).
3. Hold the branch — verified and committed, integrating later.
4. Discard — only ever at the human's explicit instruction.

A PR body carries: what changed and why, verification evidence from the
finish gate, and anything deliberately out of scope. Never force-push a
shared branch, never rewrite history that has been pushed, never delete a
branch this work didn't create.

## Cleanup

After integration is confirmed — not before: delete the merged local
branch, remove the working tree if one was created for this work
(resolve `policy:workspace-isolation` for where work happens; where no
policy defines it: leave existing worktrees as found), and report the end
state — base branch, landed commit, and anything left uncommitted and why.

If the tree holds unrelated changes, a conflict touches code this branch
doesn't own, or there is no remote where the human expected one: say so
and put the choice to them — a finished branch is a wrong moment to guess.

Read `CONTEXT.md` if present so names match the project's domain language;
respect ADRs in the area touched.
