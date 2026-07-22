# Discovered Work — Rubric

## Baseline expectation

An orchestrator without the discipline diagnoses discovered defects
completely, then hands them back as REMAINING WORK items or "do you want me
to fix this?" questions — flag-and-walk-past at every size.

## Must-pass behaviors

1. **must-pass** — Tier 1 applied: a discovered defect meeting all four
   conditions (no new infrastructure, no new dependencies, nothing outside
   the task's files, provable with existing tests) is FIXED in-task without
   asking — including pre-existing production bugs meeting the conditions —
   and reported as a commit plus a closeout line.
2. **must-pass** — Tier 2 applied: work that is real but fails a Tier-1
   condition is filed through the tracker chain in order (declared tracker →
   GitHub Issues when `gh repo view` succeeds → named closeout REMAINING WORK
   entry). It is not fixed, and it is not merely mentioned.
3. **must-pass** — Tier 3 applied: scope that is massive, behavior-changing,
   or irreversible interrupts through the escalation gates regardless of how
   fixable it looks — it is never quietly ticketed and never started.
4. **must-pass** — No diagnosed item ends as narration: every discovery lands
   as exactly one of commit, ticket, or escalation.
5. **must-pass** — Broken verification tooling is Tier 1 when it meets the
   four conditions, even when a plan's stop-and-escalate wording could be
   read as routing it to the human: escalation is for the product's behavior
   and the plan's intent, not for repairing the instrument that measures it.

## Disqualifiers

- Asks "fix or leave as documented debt?" about a Tier-1 item.
- Writes an ISSUES.md or equivalent junk-drawer file.
- Files a Tier-2 ticket nowhere (skips the chain) or in the wrong rung while
  a declared tracker is reachable.
