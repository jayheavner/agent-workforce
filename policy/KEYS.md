# Policy key registry — contract version 1

Canonical key names. Framework skills reference keys ONLY as `policy:<key>`
tokens using these names; install.sh validates every token against this file.
Key evolution is expand-contract: new key beside old, old honored one MAJOR
with a tombstone line here, then removed.

Each key notes its consumers (audited 2026-07-12). "via reviewing" means the
key is applied through reviewing's standards axis ("any other keys the change
touches") rather than a named consult sentence — observed live in the
finishing-a-branch eval record for `docstrings`.

## build-policy
- coverage — numeric test-coverage gate, scoped by work tier (consumers: tdd, reviewing)
- unit-test-speed — unit suite time/isolation budget (consumers: via reviewing)
- function-size — size smell threshold (consumers: via reviewing)
- docstrings — documentation mandate (consumers: via reviewing; observed in finishing-a-branch eval runs)
- git-conventions — commit/branch/init rules (consumers: finishing-a-branch)
- dependency-freshness — how dependency versions are chosen and pinned (consumers: planning)
- workspace-isolation — where code-writing work happens (worktree rules) (consumers: planning, tdd, debugging, finishing-a-branch)
- test-naming — recommended test naming convention (consumers: via reviewing)

## review-policy
- logging — log format + security rules (consumers: reviewing)

## process-policy
- work-tiers — tier names + gate routes (consumers: none directly; referenced by coverage policy *values*, which scope gates by tier)
- ticket-format — ticket templates + tracker specifics (consumers: write-ticket, review-ticket, close-ticket)
- closeout-integration — how finished work leaves the checkout after the local commit: `commit` | `push` | `pr` | `pr-merge` | `ask` (consumers: closeout, orchestrator agent; registered 2026-07-20 after the innovation-awards run needed "push it" / "merge it" prompted by hand)
- discovered-work — disposition of defects/debt found mid-task: fix / ticket / stop tiers with the tracker resolution chain (consumers: orchestrator agent, closeout; registered 2026-07-22 after the EA session flagged-and-walked-past a fully-diagnosed broken check twice)

## Removed keys (tombstones)

- `spec-first` — removed 2026-07-12. Never consumed by any skill; the
  sequencing it named (interview → spec → plan → code) is the framework's
  own workflow, so the knob was redundant. Re-register if a skill ever
  needs a project-configurable override for it.
- `iac-toolchain` — removed 2026-07-12. Never consumed by any skill.
  Re-register alongside an infrastructure pack that actually reads it
  (expand-contract makes this cheap).
