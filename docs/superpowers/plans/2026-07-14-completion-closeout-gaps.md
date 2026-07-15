# Completion Closeout Gaps — Implementation Plan

## Goal

Add an auditable, safe closeout layer that exposes Git cleanup candidates,
records project-memory state honestly, and makes final completion claims carry
evidence across all relevant dimensions.

## Architecture

`bin/agent-workforce-closeout` is a read-only Bash CLI around `git -C`. It emits
human-readable output by default and stable JSON when requested. The skills and
agent contracts consume that audit and require a final closeout ledger. Project
memory is a documented `docs/memory/` artifact, deliberately separate from
personal Codex memory.

## Tech stack

Bash, Git, jq for JSON validation in tests, Markdown skill contracts, and the
repository's existing shell-test convention.

## Global constraints

- Workspace isolation: “the project checkout or worktree selected when the orchestrator session starts is the task workspace”; source: project policy.
- Git conventions: Conventional Commits, commit per green cycle, and the commit message says why; source: project policy.
- Coverage: this is documentation/CLI work; focused shell tests are required, with no numeric coverage gate; source: project policy.
- Security: no secrets in files or output; read-only audit by default; source: design above and handling-secrets discipline.
- Existing dirty changes are user-owned and must remain un-staged and unmodified unless directly required by this plan.

## Task 1 — Add the read-only closeout audit

**Files**

- Create: `bin/agent-workforce-closeout`
- Create: `tests/test_closeout_audit.sh`

**Interface**

```text
bin/agent-workforce-closeout [--repo PATH] [--base BRANCH] [--format text|json]
```

The command exits `0` for a valid repository, `2` for invalid arguments or a
non-repository path, and never edits files or Git refs. JSON contains:
`repository`, `current_branch`, `base_branch`, `head`, `dirty`, `branches`,
`worktrees`, and `cleanup_candidates`.

**Steps**

1. Write `tests/test_closeout_audit.sh` with a temporary Git repository that
   creates: a committed `main`, a merged `codex/merged` branch, an unmerged
   `codex/open` branch, and a clean linked worktree for `codex/merged`. Assert
   that `--format json --base main` returns valid JSON and the expected branch,
   worktree, dirty, and cleanup-candidate values.
2. Run `bash tests/test_closeout_audit.sh`; observe the concrete failure that
   `bin/agent-workforce-closeout` does not exist.
3. Write `bin/agent-workforce-closeout` with the exact interface above. Resolve
   the repository with `git -C`, choose `main`, then `master`, then the current
   branch when `--base` is omitted, parse `git worktree list --porcelain`, and
   mark a local branch as a cleanup candidate only when it is merged into the
   base, is not the current/base branch, and is not checked out in a worktree.
   Mark a worktree as a candidate only when it is non-current, attached to a
   merged branch, and clean. Emit JSON through `jq -n` and text from the same
   collected values.
4. Run `bash tests/test_closeout_audit.sh`; require the suite's explicit PASS
   line and valid-JSON assertion.
5. Run `bash -n bin/agent-workforce-closeout` and commit only the new CLI and
   focused test with `git add bin/agent-workforce-closeout tests/test_closeout_audit.sh`
   and `git commit -m "feat: add read-only closeout audit"` if the human has
   authorized commits. If the checkout's unrelated dirty state makes that
   unsafe, leave the files uncommitted and report the exact paths.

## Task 2 — Define durable project-memory handoff

**Files**

- Create: `docs/memory/README.md`
- Modify: `skills/finishing-a-branch/SKILL.md`
- Modify: `skills/agent-workforce/SKILL.md`
- Modify: `agents/orchestrator.md`

**Interface**

Project-memory records use `docs/memory/YYYY-MM-DD-<slug>.md` and contain:
`Scope`, `Reusable facts`, `Decisions and why`, `Landmines`, `Verification`,
`Source paths`, and `Secret handling`. The closeout ledger's `memory` field is
one of `not requested`, `not reusable`, `recorded: <path>`, or `pending human
approval: <proposed path>`.

**Steps**

1. Extend `tests/test_closeout_audit.sh` with fixed-string assertions for the
   memory schema, the eight closeout-ledger fields, and the rule that cleanup is
   proposed only after confirmed integration. Run it and observe failures for
   each missing contract.
2. Create `docs/memory/README.md` with the exact record path, required headings,
   no-secrets rule, source-reading rule, and explicit statement that these are
   project records rather than personal Codex memory.
3. Add the closeout ledger and memory-state rules to the three workflow files.
   Keep the existing deployment gate, verification gate, selective staging, and
   post-integration cleanup rules intact.
4. Run `bash tests/test_closeout_audit.sh` and require all contract assertions
   to pass.
5. Run `git diff --check` and commit only these workflow/documentation files
   with `git add docs/memory/README.md skills/finishing-a-branch/SKILL.md
   skills/agent-workforce/SKILL.md agents/orchestrator.md` and
   `git commit -m "docs: make completion closeout explicit"` if authorized;
   otherwise leave them uncommitted and report them.

## Task 3 — Full verification and handoff

**Files**

- Modify: `docs/STATUS-2026-07-14-completion-closeout-gaps.md`
- Modify: `install.sh`

**Steps**

1. Write a status note listing the acceptance criteria, exact commands, and
   current proven/unrun state; do not claim the full installer suite passed
   before running it.
2. Run `bash tests/test_closeout_audit.sh` and `bash -n bin/agent-workforce-closeout`.
3. Run `bash tests/test_plugin_mode.sh`, `bash tests/test_policy_hooks.sh`,
   `bash tests/test_dispatch_guard.sh`, `bash tests/test_cost_hook.sh`,
   `bash tests/test_decision_discipline_drift.sh`, and
   `bash tests/test_gap_loop_text.sh`; record each actual result. Keep
   `tests/test_closeout_audit.sh` in the install validation list so future
   installs fail loudly if the closeout contract drifts.
4. Run `git diff --check`, inspect the complete diff against `HEAD`, and update
   the status note with pass/fail/unchecked evidence and remaining human gates.
5. Do not delete branches, worktrees, or unrelated files. Report the closeout
   audit's candidates and the exact human-confirmation step still required.

## Self-review checklist

- Every design requirement maps to a task.
- The CLI has no mutation path.
- JSON and text are derived from the same Git observations.
- Personal memory is never represented as updated without an explicit record
  path and human-authorized action.
- Existing dirty changes are not staged or discarded.
