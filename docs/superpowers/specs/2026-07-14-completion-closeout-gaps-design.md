# Completion Closeout Gaps — Design

**Date:** 2026-07-14
**Status:** Approved for implementation in this task
**Scope:** local framework behavior; no cloud mutation and no personal-memory write

## Goal

Make completion auditable across verification, documentation, memory handoff,
Git state, deployment, and integration without silently deleting work or
claiming that personal memory was updated when it was not.

## Problem

The workforce already verifies work, writes status notes, commits implementation
cycles, and guards deployment. It does not yet provide one closeout ledger, a
machine-readable branch/worktree inventory, or a durable project-memory format.
The existing branch-finishing guidance also leaves the memory state implicit.

## Decisions

1. **Read-only audit first.** Add `bin/agent-workforce-closeout`, which reports
   current branch, dirty state, base-branch ancestry, local branches, worktrees,
   and cleanup candidates. It never mutates Git state.
2. **Explicit cleanup only.** A cleanup candidate is evidence, not permission.
   The finishing workflow may propose exact `git branch --delete` and
   `git worktree remove` commands only after integration is confirmed and the
   target is clean, merged, non-current, and owned by the task.
3. **Project memory, not implicit personal memory.** Add `docs/memory/README.md`
   defining reusable project-memory records. The scribe may create those records
   when requested or when the human approves recording a reusable decision. The
   workflow must state `not requested`, `not reusable`, or the exact record path;
   it must never imply that `$HOME/.codex/memories` or another personal memory
   store was changed.
4. **Closeout ledger.** The final gate must report these fields explicitly:
   `verification`, `review`, `documentation`, `memory`, `commit`, `deployment`,
   `integration`, and `cleanup`. Each field is `pass`, `fail`, `pending`, or
   `not applicable`, with evidence or the next exact action.
5. **Preserve existing boundaries.** The orchestrator still owns routing and
   gates; the builder still owns implementation commits; the deployer still
   requires deploy approval and performs smoke/rollback; unrelated dirty changes
   are never swept into a commit.

## Acceptance criteria

1. `bin/agent-workforce-closeout --help` documents read-only behavior and the
   `--repo`, `--base`, and `--format text|json` options.
2. Against a temporary repository, the audit reports the current branch, dirty
   state, selected base, merged local branches, worktrees, and cleanup candidates.
3. The JSON output is valid and contains stable top-level keys for `repository`,
   `current_branch`, `base_branch`, `dirty`, `branches`, `worktrees`, and
   `cleanup_candidates`.
4. The project-memory record format forbids secrets and distinguishes project
   records from personal memory.
5. The agent-workforce and branch-finishing instructions require the closeout
   ledger and explicit memory state, and preserve confirmation before cleanup.
6. Focused tests pass, followed by the existing plugin, policy, installer, and
   drift checks that can run without touching the user's existing profile.

## Security and safety

- The audit command performs only Git reads and local status inspection.
- No command accepts or prints credential values.
- No cleanup command is implemented in this change; proposed destructive
  commands remain human-approved actions in the finishing workflow.
- Existing uncommitted files in the checkout remain outside this change.
