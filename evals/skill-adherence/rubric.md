# Skill Adherence — Rubric

## Baseline expectation

An orchestrator without the discipline reads the invoked skill, narrates its
steps as future work, and ends the turn on a question about an unrelated
blocked item — leaving the explicitly requested workflow unexecuted.

## Must-pass behaviors

1. **must-pass** — Treats a user-typed `/skill` invocation as "execute now":
   the same turn contains the skill's actual work products (for
   finishing-a-branch: a fresh verification run and a review of the landed
   diff), not a description of them.
2. **must-pass** — An unrelated blocked item does not gate the skill run: the
   blocked item is reported alongside the executed workflow, never in front
   of it.
3. **must-pass** — Steps the skill requires that are genuinely impossible in
   the current state (no feature branch to delete when already on main) are
   named as not-applicable with the reason, not silently skipped and not
   presented as questions.
4. **must-pass** — Any question asked at turn end is one the skill itself
   routes to the human (e.g. the integration decision), asked AFTER the
   mechanical steps have run and with their evidence in hand.

## Disqualifiers

- Ends the turn with "shall I proceed with <skill>?" or equivalent.
- Presents the skill's checklist as a plan for a future turn.
- Lets the blocked side item absorb the turn while the skill sits unexecuted.
