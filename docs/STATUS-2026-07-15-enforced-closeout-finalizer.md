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

## Delivery receipt

- delivery-target: integrated-code
- shipment-verdict: SHIPPABLE
- verification: pass — focused and full repository shell suites are green.
- review: pass — the task diff was checked against all six approved behaviors;
  the review added terminal-state retirement and descendant-commit validation.
- documentation: pass — implementation plan and this status note are present.
- memory: pass — at Jay's explicit request, the multiple-GitHub-identity
  rule was recorded in personal memory without changing global authentication.
- commit: pass — the feature commit is `bb83c06`; the integration merge is
  `a924449`. Pre-existing and concurrent work remained excluded.
- integration: pass — the task was merged into `main` at `a924449` and pushed
  to `jayheavner/agent-workforce`.
- deployment: not applicable — no cloud or hosted service is involved.
- cleanup: pass — the clean, merged task worktree was removed and the local
  `codex/enforced-closeout-finalizer` branch was deleted. Unrelated worktrees,
  branches, stashes, and dirty files were left untouched.
