---
name: reviewing
description: Code-review craft — review a change against project standards and against its originating requirement (spec fidelity), with severity triage and locations + fixes. Use when reviewing code, a pull request, or a task's diff before merge.
---

# Reviewing

Job: judge a change on two axes and report findings a stranger can act on.
Review the diff, not the description — claims about what a change does are
verified against the code.

## Axis 1 — Standards

Resolve `policy:logging`, `policy:coverage`, and any other keys the change
touches from the project policy and state each resolved value and its source —
project policy / user policy / judgment default — before applying it. Where no
policy defines one: for `coverage`, no numeric gate, TDD always; for
`logging`, structured, and never log secrets, request bodies, auth headers,
cookies, query params, tokens, or passwords.
Beyond policy: naming, duplication, dead code, error handling that swallows,
tests that assert nothing (see `tdd`'s anti-patterns), secrets or sensitive
data in code and logs.

## Axis 2 — Spec fidelity

Does the change do what its originating requirement says — and nothing else?
- Every requirement line maps to code in the diff; list gaps.
- Every hunk in the diff maps to a requirement; anything else is out-of-scope
  and gets flagged, even if it is an improvement. Out-of-scope is a finding,
  not a crime — but it is the author's decision to split, not the reviewer's
  to wave through.

## Findings

Each finding: **severity** (blocking / should-fix / nit), **location**
(file:line), **the defect in one sentence**, **a specific fix**. Blocking =
correctness, security, data loss, policy violation. Never bundle two defects
in one finding.

## Verdict

Approve only when there are no blocking findings and you have actually read
every hunk. State what was reviewed (the diff range/commit) so the approval is
scoped. What-went-well is signal for the author, not politeness — name one
thing worth repeating.

On a diff too large to read hunk-by-hunk in one pass, don't skim it and approve
anyway — that is a false green. Read in risk order (the logic and the security-
and data-touching hunks first, mechanical churn like renames or generated files
last), and if you must stop before covering it all, approve only the range you
actually read and say plainly what went unreviewed. An honest partial review
beats a blanket approval that read none of it closely.

## Traps

- Reviewing the PR description instead of the diff.
- Style dominance: ten nits and a missed injection flaw is a failed review —
  spend attention proportional to severity.
- "Tests pass" as approval: tests prove what tests cover; the review covers
  the rest.
