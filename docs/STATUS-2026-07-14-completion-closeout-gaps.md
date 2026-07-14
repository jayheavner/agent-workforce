# STATUS: completion-closeout-gaps

## Scope

Implemented the 2026-07-14 completion-closeout gap plan: a read-only Git
closeout audit, project-memory record guidance, and explicit closeout ledger
requirements for verification, review, documentation, memory, commit,
deployment, integration, and cleanup.

## Artifacts

- Design: `docs/superpowers/specs/2026-07-14-completion-closeout-gaps-design.md`
- Plan: `docs/superpowers/plans/2026-07-14-completion-closeout-gaps.md`
- Audit CLI: `bin/agent-workforce-closeout`
- Focused test: `tests/test_closeout_audit.sh`
- Installer validation: `install.sh` now runs the focused closeout test.
- Project-memory format: `docs/memory/README.md`
- Workflow contracts: `skills/closeout/SKILL.md`,
  `skills/finishing-a-branch/SKILL.md`, `skills/agent-workforce/SKILL.md`,
  `agents/orchestrator.md`

## Closeout ledger

- `verification: pass` — `bash tests/test_closeout_audit.sh` reported
  `PASS=23 FAIL=0`; `bash -n bin/agent-workforce-closeout` passed; policy,
  plugin, dispatch, cost, decision-discipline, gap-loop, installer-sandbox,
  ChatGPT-plugin, Codex-profile, and `git diff --check` checks passed. Exact
  suite results are recorded below.
- `review: pending` — no independent reviewer pass was run in this single
  thread. The full diff still requires a separate review before integration.
- `documentation: pass` — design, plan, project-memory schema, workflow
  contracts, and this status note were written.
- `memory: not requested` — no personal Codex memory was changed. The new
  `docs/memory/README.md` defines the approved project-record format.
- `commit: pass` — commit `55aa9ef` (`feat: add Codex integration and closeout
  controls`) contains the scoped workforce/plugin/Codex/closeout files. The
  unrelated audio, generator script, and `__pycache__` remain uncommitted.
- `deployment: not applicable` — this change is local framework, documentation,
  and CLI work; no cloud mutation was requested or performed.
- `integration: pending` — the feature branch is not merged; push does not
  perform a merge or PR. The human must choose the later merge/PR path.
- `cleanup: pending` — the audit found `codex/integrate-skills-upstream` as a
  merged local-branch candidate, but this task did not create it and the current
  checkout is dirty. No branch or worktree was removed.

## Verification evidence

| Command | Result |
|---|---|
| `bash tests/test_closeout_audit.sh` | `PASS=23 FAIL=0` |
| `bash -n bin/agent-workforce-closeout` | exit 0 |
| `bash tests/test_policy_hooks.sh` | `passed=191 failed=0` |
| `bash tests/test_plugin_mode.sh` | `PASS=20 FAIL=0` |
| `bash tests/test_dispatch_guard.sh` | `PASS=32 FAIL=0` |
| `bash tests/test_cost_hook.sh` | `passed=51 failed=0` |
| `bash tests/test_decision_discipline_drift.sh` | `PASS=3 FAIL=0` |
| `bash tests/test_gap_loop_text.sh` | `passed=16 failed=0` |
| `bash tests/test_install_skills.sh` | `PASS=36 FAIL=0` |
| `bash tests/test_chatgpt_plugin.sh` | `PASS=15 FAIL=0` |
| `bash tests/test_codex_profiles.sh` | `PASS=13 FAIL=0` |
| `git diff --check` | exit 0 |

`AGENT_TEAM_SKIP_INSTALL_TEST=1 bash install.sh --check --profile
"$HOME/.claude"` was run read-only and exited 1 because the installed profile
is stale relative to the existing dirty checkout. It reported stale files and
new uninstalled files; reinstalling the profile was intentionally not performed
without explicit authorization. A full `bash install.sh --check` rerun also
executed the newly integrated closeout test before reporting the same stale/new
profile state.

## Current audit

`bin/agent-workforce-closeout --repo . --base main --format text` reports:

- current branch: `codex/finishing-work`
- base: `main`
- dirty: `true`
- merged branch candidate: `codex/integrate-skills-upstream`
- worktree candidates: none

The candidate is not eligible for automatic deletion because ownership was not
established by this task.
