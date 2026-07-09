# Status: Vendor Org Skills

## Task

The agent team depends on ten "org skills" installed in `~/.claude/skills/` that were never checked into the repo. A fresh clone fails at install.sh because these skills are missing. Solution: review and modernize each skill for present-day quality, vendor them into the repo, wire them into install.sh and README.

## Tier

Large / high-risk. Full software route.

## Phase Completed

Architect implementation plan.

**Plan location:** docs/superpowers/plans/2026-07-09-vendor-org-skills.md

**SPEC GATE passed.** Human decisions applied:
- **audit-requirements-document:** Option B (drop Python, vendor rewritten SKILL.md + patterns.md only)
- **secure-secrets:** Rework to service-account auth + no plaintext secrets
- **writing-business-requirements:** Leave out orphan files, vendor SKILL.md only

## Per-Skill Verdicts

### Keep (minor cleanup needed)

1. **coding-standards** — Core code quality rules; used correctly; minor polish to examples
2. **code-review** — Sound review discipline; aligns with team practices; update dated references
3. **task-verification** — Dependency on Asana API correct; verify token scope
4. **writing-business-requirements** — Comprehensive BABOK-aligned standards; clean; reference audit skill integration
5. **ux-to-ui-design** — Design workflow documentation; requires context pass-through testing
6. **vendoring (references skill)** — Guides vendor discipline; ready for repo

### Modernize (drop claude-mem deps, fix contradictions)

1. **write-ticket** — Create tickets; drops broken claude-mem dependency; resolves contradictions with team conventions on acceptance criteria format
2. **review-ticket** — Ticket review gate; drops broken claude-mem dependency; aligns gate criteria with coding-standards and code-review
3. **plan-review** — Design review gate; addresses timeline/phase contradiction with CLAUDE.md (which forbids time/effort estimates); aligns acceptance criteria with team patterns

### Rework (security violations and pipeline bugs)

1. **secure-secrets** — High-priority: plaintext secret backups and desktop-app auth contradict CLAUDE.md global security policy; must switch to service-account-only model (1Password CLI) for all secret handling
2. **audit-requirements-document** — Functional audit skill with two blocker issues:
   - Case-sensitivity bug in requirement ID matching (FR-001 vs fr-001)
   - Python pipeline uninstallable (missing __init__.py, unresolved dependencies); currently vendor-unready

## Vendoring Approach

**New top-level skills/ directory** mirrors installed layout at `~/.claude/skills/`; tracks all ten skills.

**Allowlist curation** — Skills are vendored with explicit manifest entry; resolve_skill gains repo-tree check to validate against manifest.

**Manifest and drift detection** — `.claude-project` manifest + `--check` flag extended to skills; detects drift when vendored skills differ from installed versions.

**Sandboxed install test** — New test harness validates that fresh clone → install.sh → resolve_skill finds all skills in repo; runs before final commit.

## Implementation Plan

**Scope:** 13 tasks across 3 phases

**Phase 1: Vendor 10 Skills (Tasks 1–10)**
- Task 1–10: Modernize and vendor each skill to repo

**Phase 2: Installer Changes with TDD Test (Tasks 11–12)**
- Task 11: Add install test (validates fresh clone → install.sh → resolve_skill finds all skills)
- Task 12: Update install.sh to copy skills from repo

**Phase 3: README/Docs (Task 13)**
- Task 13: Update README with new install steps and skill vendoring documentation

**Design Fix Applied:** Install test infinite recursion resolved with AGENT_TEAM_SKIP_INSTALL_TEST guard in both install.sh and install test.

## Execution Progress

**2026-07-09: PLAN GATE passed; execution style chosen: task-by-task with review.**

Phase 1 progress: 8 of 10 skills vendored (coding-standards, code-review, write-ticket, review-ticket, task-verification, writing-business-requirements, plan-review, ux-to-ui-design). All file content verified correct and byte-hash-verified on disk. The three references/coding-standards.md copies are hash-identical. Tasks 3 (secure-secrets) and 8 (audit-requirements-document) not yet started.

INCIDENT: The orchestrator dispatched 7 builders concurrently against one shared git working tree; their git add/commit calls interleaved, so commit messages do not match their diffs across approximately 9 commits. No content was lost or corrupted — every task's file is present and byte-correct; only the commit-history labeling is scrambled. Root cause: parallel builders sharing one git index with no locking. Fix pending: serialize remaining work and normalize commit history.

Next: Repair commit history, then vendor Tasks 3 and 8 serially, then Phase 2 (installer) and Phase 3 (docs).

**2026-07-09: PHASE 1 COMPLETE — All 10 skills vendored. Commit history repaired.**

Commit-history repair: chose re-split into per-task commits; 8 clean per-skill commits rebuilt from verified tree, content byte-identical (proven by before/after shasum). Boundary was the clean coding-standards commit.

All 10 skills vendored. Artifacts produced: 14 vendored files total (10 SKILL.md + 3 references/coding-standards.md + 1 audit patterns.md). Task distribution: Tasks 1–2, 4–7, 9–10 (8 keep/modernize skills) executed in parallel; Tasks 3 and 8 (2 rework/security-critical skills) executed serially after commit repair.

**Security review (reviewer on top model)** of the two security-critical skills: initially found 1 HIGH (secure-secrets had 3 bare `op read` calls that print full secrets to the transcript) + 2 MEDIUM + 2 LOW. All fixed in one builder repair loop; re-review APPROVED. audit skill clean on first pass.

**Hygiene sweep** of all 10 skills clean: no /Users/jay paths, no emoji, no claude-mem references, no CLAUDE.md excerpts, skill name matches directory name, 3 references copies hash-identical to source.

**Minor open note (non-blocking, permitted by criteria):** secure-secrets Quick Reference shows bare `op read` reference strings for a human to copy; reviewer flagged as optional belt-and-suspenders, not a defect. Left as-is per acceptance criteria.

## Next Phase

Phase 2 (installer TDD: Task 11 failing test + Task 12 install/validate/backup/rollback/manifest/check for skills), then Phase 3 (README), then verifier acceptance run.

## Completion Note (2026-07-09)

TASK COMPLETE. Original bug fixed: fresh clone now installs cleanly; on this machine `bash install.sh` reports "10 agents + 10 skills installed" and `bash install.sh --check` reports OK.

Phase 2 (installer) complete: install.sh extended (resolve_skill repo-tree check, 3 pre-copy skills validations, hash-identity guard, AGENT_TEAM_SKIP_INSTALL_TEST recursion guard in both install.sh and the test, nested backup/restore/cleanup_fresh/install loops, manifest skills producer, --check skills coverage). New tests/test_install_skills.sh, 17 assertions, all pass.

Phase 3 (README) complete: org skills documented as vendored/installed, not external dependency; drift-detection section covers skills.

Verifier: all 8 acceptance criteria PASS (fresh-machine sandbox install, ten uppercase SKILL.md, --check OK, drift/missing detection, existing suites unchanged at 191/51/22 pass, hygiene clean, no Python, real-machine install+check).

Reviewer: approve-with-nits — 2 LOW test-robustness nits (subshell false-pass on empty input; grep -x dot-wildcard), both fixed in a follow-up builder pass; test still 17/17 green.

All 13 plan tasks committed. Commit history clean (per-task commits after the earlier concurrency repair).

Closeout cost: reported as a blended ESTIMATE (~$12 across ~19 dispatches) because the on-disk exact cost files did not cleanly represent this session (one marked ok belonged to a different session; the session's own file was marked unavailable/model-not-in-rates). Flag for follow-up: the cost hook could not price this session — worth checking the model-rates config covers the models used.

No open blockers. Task done.

## Open Questions

None outstanding.
