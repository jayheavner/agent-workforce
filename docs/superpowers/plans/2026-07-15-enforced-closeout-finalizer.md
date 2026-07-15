# Enforced Closeout Finalizer — Implementation Plan

**Goal:** Prevent an Agent Workforce repository task from stopping with task-owned uncommitted files, stale verification/review, or eligible task-created cleanup still outstanding.

**Architecture:** A stateful Claude hook records the repository baseline before the first mutating specialist dispatch, records verifier/reviewer terminal markers, and evaluates the main agent's `Stop` event. The hook blocks only actionable local incompleteness and tells the orchestrator to dispatch the existing executor as finalizer; it never commits, pushes, deletes, or edits the repository itself. Existing delivery-receipt linting remains the structural completion-claim authority.

**Tech Stack:** Python 3 standard library, Git CLI, Claude Code hook JSON, Bash test runner, `coverage.py` for the policy coverage gate.

## Global Constraints

- **workspace-isolation (project policy):** “the project checkout or worktree selected when the orchestrator session starts is the task workspace. Builder, verifier, reviewer, and deployer use that same explicit path for the full route; do not create a nested worktree from inside a specialist dispatch. Run only one code-writing task in a checkout at a time.”
- **coverage (project policy):** “≥90% line coverage for standard/large-tier work.”
- **git-conventions (project policy):** “pre-commit secret-blocking hooks on every project; Conventional Commits; commit per green cycle, message says why.”
- **logging (project policy):** structured JSON for persisted state; never record secrets, prompts, request bodies, auth headers, cookies, query parameters, tokens, or passwords.
- The hook must never stage, commit, push, merge, delete a branch, or remove a worktree.
- Baseline dirt is user-owned: a task may leave it byte-for-byte unchanged, but resolving, changing, staging, or committing it is treated as task residue until reconciled.

## Approved behavior

1. A repository implementation request authorizes focused local commits unless the user explicitly says not to commit.
2. Final Scribe artifacts are followed by an Executor finalization pass before completion.
3. The first mutating specialist dispatch records HEAD, branch/worktree inventory, and content/index signatures for every initially dirty path.
4. `SHIPPABLE` is blocked unless the final report has a valid delivery receipt, task-owned dirt is absent, and any Builder work has fresh passing verifier and reviewer markers.
5. Clean merged non-current branches/worktrees created after the baseline are cleanup blockers for `SHIPPABLE`; pre-existing branches/worktrees are never cleanup blockers.
6. An honest `NOT SHIPPABLE` report may stop when there is no actionable task-owned repository residue. A genuine human-decision pause remains allowed.

## Task 1 — Behavioral guard seam

**Files**

- Create: `tests/test_agent_team_closeout.py`
- Create: `tests/test_closeout_hook.sh`
- Create: `hooks/agent_team_closeout.py`

**Interface**

- `python3 hooks/agent_team_closeout.py dispatch` consumes a `PreToolUse(Agent)` JSON object.
- `python3 hooks/agent_team_closeout.py subagent-stop` consumes a `SubagentStop` JSON object.
- `python3 hooks/agent_team_closeout.py stop` consumes a `Stop` JSON object and emits either no output or `{"decision":"block","reason":"..."}`.
- `AGENT_TEAM_CLOSEOUT_DIR` redirects state for tests; default is `~/.claude/state/agent-workforce-closeout`.

**Steps**

- [x] Write a failing test that initializes a baseline, creates an untracked task file, and expects `Stop` to block with a finalizer instruction.
- [x] Run `bash tests/test_closeout_hook.sh`; expect failure because `hooks/agent_team_closeout.py` does not exist.
- [x] Implement baseline snapshots, dispatch sequencing, verifier/reviewer marker recording, receipt linting, residue comparison, and task-created cleanup detection.
- [x] Add cases for unchanged pre-existing dirt, changed pre-existing dirt, committed task files, missing/stale verifier and reviewer evidence, honest non-shippable reports, human-decision pauses, no-state sessions, and task-created cleanup candidates.
- [x] Run `bash tests/test_closeout_hook.sh`; expect all cases and `coverage report --fail-under=90` to pass.
- [x] Commit with `feat(closeout): enforce task-owned repository finalization` after integration wiring is green.

## Task 2 — Workflow and installation wiring

**Files**

- Modify: `agents/orchestrator.md`
- Modify: `agents/executor.md`
- Modify: `agents/verifier.md`
- Modify: `agents/reviewer.md`
- Modify: `skills/agent-workforce/SKILL.md`
- Modify: `skills/closeout/SKILL.md`
- Modify: `skills/finishing-a-branch/SKILL.md`
- Modify: `hooks/agent-team-plugin-router.sh`
- Modify: `hooks/hooks.json`
- Modify: `install.sh`
- Modify: `tests/test_plugin_mode.sh`
- Modify: `tests/test_completion_contract.sh`

**Interface**

- Verifier final line: `WORKFORCE_VERIFICATION: verdict=<SHIPPABLE|NOT_SHIPPABLE|UNCHECKED>; full_suite=<pass|fail|unchecked>`.
- Reviewer final line: `WORKFORCE_REVIEW: verdict=<approve|approve-with-nits|request-changes>`.
- Orchestrator closeout order: final Scribe → Executor finalizer → read-only closeout/receipt verification → final response.

**Steps**

- [x] Add failing contract/plugin tests for the three hook events, installed hook/tool files, terminal markers, and finalizer route.
- [x] Run the focused tests and capture the missing-registration failure.
- [x] Register dispatch, subagent-stop, and stop modes in live-plugin and snapshot configurations; copy required hook support during snapshot installation.
- [x] Amend role/workflow contracts so local commits are default-authorized, late documentation is finalized, and only task-created eligible cleanup is automatic.
- [x] Run focused tests, installer sandbox tests, plugin tests, and syntax/JSON validation.

## Task 3 — Final verification and review

- [x] Run every repository test under `tests/test_*.sh` after the final edit and read the complete output.
- [x] Run `git diff --check`.
- [x] Review every task hunk against the six approved behaviors and confirm that unrelated dirty files are absent from the staged diff.
- [x] Stage only this plan, hook implementation, tests, and scoped contract/install wiring.
- [x] Commit using Conventional Commits; leave all pre-existing dirty and untracked files untouched.

## Self-review

- **Coverage:** all six approved behaviors map to Tasks 1–2; verification and atomic staging map to Task 3.
- **Placeholder scan:** no TBD/TODO/deferred implementation steps.
- **Consistency:** hook mode names, marker formats, state directory override, and finalizer order are identical across plan, tests, hook, and role contracts.
- **Security:** state contains Git metadata and hashes only; no prompts, transcript bodies, environment dumps, or credentials are persisted.
