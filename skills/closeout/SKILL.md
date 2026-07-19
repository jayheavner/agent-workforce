---
name: closeout
description: Finish a workforce task the same way every time — fresh verification, a focused commit, one status note, honest completion claims, and the exact whole-session cost report. Use when work is being finished, shipped, wrapped up, handed off, or reported complete.
---

# Closeout

Every task ends the same way, in this order. The Stop hook enforces the mechanical parts; this
skill is the shape of a proper ending.

## 1. Verify

Fresh verifier evidence after the final code edit — a re-review of a specific finding never
substitutes for re-verification after the code changed. A pre-existing suite failure can be
recorded as non-regression but still blocks any "shippable" claim when the delivery target
needs that suite green.

## 2. Commit

The implementation request authorizes a focused local commit of this task's delta (code, tests,
plans, status notes) unless the human explicitly opted out. Stage only the task's paths — never
`git add -A`, never baseline dirt — use the repository's commit convention, record the hash.
Pushing needs separate authority. Remove only clean, merged branches or worktrees this task
created; `bin/agent-workforce-closeout --repo <checkout> --base <base> --format text` is the
read-only audit when in doubt. Never delete by age or touch anything the task did not create.

## 3. Record

One status note (`docs/STATUS-<task-slug>.md`): outcome, evidence, commits, deviations,
decisions made-and-disclosed, anything provisional created under `growing-the-team`, and any
open follow-up. Mid-task notes exist only for genuine interruption or handoff.

## 4. Report honestly

Say exactly what was proved, in delivery terms: `implemented and locally verified`,
`deployed and smoke-checked`, `drafted, not filed`. Never "done" or "shippable" past the
evidence, and never a completion claim that hides an unrun check or a dirty tree — if
uncommitted changes remain, say what and why. Decisions made on the human's behalf are listed,
one line each.

## 5. Price exactly

The final message ends with the cost report under the heading `## Cost report` — produced by
`bin/agent-workforce-cost-report --transcript <session transcript>` (the Stop hook computes it
and hands it over if omitted). It prices the whole session, the main session included, at list
rates from the transcripts. Costs are never estimated: a model without a rate is reported as
exact unpriced token counts and the missing rate named so it can be added.
