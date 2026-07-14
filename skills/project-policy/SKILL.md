---
name: project-policy
description: Jay's org policy values — thresholds, formats, and tool mandates consulted by framework skills. Use when any framework skill resolves a policy:<key>.
policy-contract: 1
---

# Project Policy

*Resolution is per-key:* a project-scope policy (`.claude/skills/project-policy/`) overrides ONLY the keys it names and inherits the rest from user scope (`~/.claude/skills/project-policy/`); a `project-policy` skill wins over a CLAUDE.md `## Project policy` section when both exist. Skills echo the resolved value and its source.

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
