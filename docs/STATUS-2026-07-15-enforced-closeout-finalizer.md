# STATUS: enforced-closeout-finalizer

## Outcome

Repository tasks now have an enforced local closeout boundary. The workforce
records the starting Git state, requires fresh machine-readable Verifier and
Reviewer evidence after Builder work, blocks a terminal `SHIPPABLE` response
while task-owned changes or eligible task-created cleanup remain, and routes the
repair to an Executor finalizer. The hook observes and blocks; it never stages,
commits, pushes, deletes a branch, or removes a worktree itself.

## Artifacts

- Plan: `docs/superpowers/plans/2026-07-15-enforced-closeout-finalizer.md`
- Hook: `hooks/agent_team_closeout.py`
- Behavior tests: `tests/test_agent_team_closeout.py` and
  `tests/test_closeout_hook.sh`
- Live plugin wiring: `hooks/hooks.json` and
  `hooks/agent-team-plugin-router.sh`
- Snapshot wiring: `agents/orchestrator.md` and `install.sh`
- Role contracts: `agents/executor.md`, `agents/verifier.md`, and
  `agents/reviewer.md`
- Shared workflow contracts: `skills/agent-workforce/SKILL.md`,
  `skills/closeout/SKILL.md`, and `skills/finishing-a-branch/SKILL.md`

## Verification evidence

- `bash tests/test_closeout_hook.sh` — 21 tests passed; 92% line coverage.
- `bash tests/test_completion_contract.sh` — PASS=21 FAIL=0.
- `bash tests/test_agent_frontmatter.sh` — passed=31 failed=0.
- `bash tests/test_plugin_mode.sh` — PASS=27 FAIL=0.
- `bash tests/test_install_skills.sh` — PASS=36 FAIL=0.
- Every `tests/test_*.sh` script passed after the final implementation edit.
- `git diff --check` passed.

## Closeout ledger

- `verification: pass` — focused and full repository shell suites are green.
- `review: pass` — the task diff was checked against all six approved behaviors;
  the review added terminal-state retirement and descendant-commit validation.
- `documentation: pass` — implementation plan and this status note are present.
- `memory: not requested` — no personal or project memory was changed.
- `commit: pass` — the focused Conventional Commit is reported in the final
  handoff; pre-existing dirty paths are excluded.
- `deployment: not applicable` — no cloud or hosted service is involved.
- `integration: pending` — the focused commit is held on
  `codex/enforced-closeout-finalizer`; the primary `main` checkout contains
  unrelated overlapping dirty work, so no merge or push was attempted.
- `cleanup: not applicable` — the task worktree and branch are active delivery
  resources, not merged cleanup candidates. No pre-existing branch, worktree,
  stash, or dirty file was removed.
