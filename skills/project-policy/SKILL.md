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

**workspace-isolation** — one worktree per **change**, not per agent. A change is a lower-case slug naming the work, declared by one line at the start of a line in the dispatch prompt: `CHANGE: <slug>`. That declaration is the whole administration: the dispatch guard claims the change in the work register — one timecard file on disk, naming the session that owns it — and creates or adopts its worktree before the dispatched agent's first turn. Both names are derived from the slug and never passed to anyone, so there is no path to get wrong: the worktree is `<project>/.claude/worktrees/<slug>` and its ref is `refs/heads/change/<slug>`. The retired per-builder path declaration is refused by name, because a declaration no guard reads is worse than none. An agent steps into the derived path, confirms it with `git rev-parse --show-toplevel`, and works only there; it never creates a workspace itself and never writes inside another change's tree. Every dispatch of one piece of work — architect, test-author, builder, verifier, reviewer, scribe, executor, deployer — declares the same slug and lands in the same workspace, so a peer's committed work may already be in that tree. Parallelism is per change: two changes run at once, while one change admits one writing turn at a time, and the register hands that writer slot to one dispatch at a time. Enforced, not advisory: the worktree guard resolves confinement from the register and refuses every write and every shell command outside the change's worktree, while reads are never gated. At closeout the session states each held change's disposition — integrated into a named ref, kept for a tracker reference, or abandoned; integration is a dispatched executor command (`agent-team-workspace.sh integrate`), never something the closeout hook performs, and it is what merges the change, removes its worktree, deletes its ref, and releases its timecard.

**test-naming** — recommended: test_<what>_<condition>_<expected>; not a gate.

## review-policy

**logging** — structured JSON, levels INFO/WARNING/ERROR/CRITICAL; error paths and state transitions must log; never log secrets, request bodies, auth headers, cookies, query params, tokens, or passwords.

## process-policy

**work-tiers** — small / standard / large-high-risk; the tier is stated in the dispatch.

**ticket-format** — Asana; parent tasks carry WHAT/WHY, subtasks carry HOW; one layer deep (parent → subtasks); templates and mechanics per the ticketing-asana pack.

**closeout-integration** — resolution order (decided 2026-07-22 after an intake question re-asked what a work order had already stated): (1) a project pin; (2) explicit intent in the task text — a work order that says "ship PRs," "merge to main," or "commit only" IS the resolution, standing authority through closeout, never re-asked; (3) only when both are silent, `ask` once at task intake (before the first dispatch). Values a project may pin: `commit` (stop at the focused local commit), `push` (push the current branch when the remote allows it), `pr` (push a feature branch and open a PR; the human merges), `pr-merge` (branch → PR → merge → clean up branches). A pin or stated intent skips the intake question entirely.

**discovered-work** — fix / ticket / stop; never narrate. Defects or debt discovered mid-task get exactly one disposition. **Fix now** when all four hold: no new infrastructure, no new dependencies, nothing outside the task's files, provable with the existing test apparatus — pre-existing production bugs included; the commit plus a closeout line is the record. **Ticket** when real but any condition fails, routed by the tracker chain: the project's declared tracker (`.workforce/project.json` `tracker`) → GitHub Issues if `gh repo view` succeeds → a named entry in the closeout REMAINING WORK section (the floor; never an ISSUES.md). **Stop and escalate** when massive, behavior/contract-changing, irreversible, or contrary to a recorded human decision — size overrides everything. GitHub tickets filed by the workforce carry the label `workforce`; the session-start hook surfaces open labeled issues at every launch, so filed work is announced, never hunted for. Decided 2026-07-22.
