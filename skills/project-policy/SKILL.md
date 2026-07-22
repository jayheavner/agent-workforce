---
name: project-policy
description: Jay's org policy values — thresholds, formats, and tool mandates consulted by framework skills. Use when any framework skill resolves a policy:<key>.
policy-contract: 1
---

# Project Policy

*Resolution is per-key:* use the closest-scope `project-policy` skill exposed by the active surface. A project-scope policy overrides ONLY the keys it names and inherits the rest from user or plugin scope. On Claude Code this commonly resolves through `.claude/skills/project-policy/` and `~/.claude/skills/project-policy/`; on ChatGPT/Codex use the active project, plugin, and user skill layers. A `project-policy` skill wins over a `## Project policy` section in `CLAUDE.md` or `AGENTS.md` when both exist. Skills echo the resolved value and its source.

## build-policy

**coverage** — ≥90% line coverage for standard/large-tier work; trivial/small-tier work requires TDD (test-first at agreed seams) but no numeric threshold. The tier comes from the dispatch.

**unit-test-speed** — whole unit tier < 5s, no network, mock all external deps.

**function-size** — single responsibility; typically < 50 lines; longer needs a reason in review.

**docstrings** — every module/function/class: one-line summary, why it exists, parameters, return value, exceptions raised.

**git-conventions** — version control initialized before application code (git init → .gitignore committed → code); pre-commit secret-blocking hooks on every project; Conventional Commits; commit per green cycle, message says why.

**dependency-freshness** — versions verified current by web search (LTS + security advisories) and pinned exactly; never from memory; no ranges.

**workspace-isolation** — the project checkout or worktree selected when the orchestrator session starts is the task workspace. Builder, verifier, reviewer, and deployer use that same explicit path for the full route; do not create a nested worktree from inside a specialist dispatch. Run only one code-writing task in a checkout at a time. Concurrent tasks require separate human-created checkouts or orchestrator sessions.

**test-naming** — recommended: test_<what>_<condition>_<expected>; not a gate.

## review-policy

**logging** — structured JSON, levels INFO/WARNING/ERROR/CRITICAL; error paths and state transitions must log; never log secrets, request bodies, auth headers, cookies, query params, tokens, or passwords.

## process-policy

**work-tiers** — small / standard / large-high-risk; the tier is stated in the dispatch.

**ticket-format** — Asana; parent tasks carry WHAT/WHY, subtasks carry HOW; one layer deep (parent → subtasks); templates and mechanics per the ticketing-asana pack.

**closeout-integration** — resolution order (decided 2026-07-22 after an intake question re-asked what a work order had already stated): (1) a project pin; (2) explicit intent in the task text — a work order that says "ship PRs," "merge to main," or "commit only" IS the resolution, standing authority through closeout, never re-asked; (3) only when both are silent, `ask` once at task intake (before the first dispatch). Values a project may pin: `commit` (stop at the focused local commit), `push` (push the current branch when the remote allows it), `pr` (push a feature branch and open a PR; the human merges), `pr-merge` (branch → PR → merge → clean up branches). A pin or stated intent skips the intake question entirely.

**discovered-work** — fix / ticket / stop; never narrate. Defects or debt discovered mid-task get exactly one disposition. **Fix now** when all four hold: no new infrastructure, no new dependencies, nothing outside the task's files, provable with the existing test apparatus — pre-existing production bugs included; the commit plus a closeout line is the record. **Ticket** when real but any condition fails, routed by the tracker chain: the project's declared tracker (`.workforce/project.json` `tracker`) → GitHub Issues if `gh repo view` succeeds → a named entry in the closeout REMAINING WORK section (the floor; never an ISSUES.md). **Stop and escalate** when massive, behavior/contract-changing, irreversible, or contrary to a recorded human decision — size overrides everything. GitHub tickets filed by the workforce carry the label `workforce`; the session-start hook surfaces open labeled issues at every launch, so filed work is announced, never hunted for. Decided 2026-07-22.
