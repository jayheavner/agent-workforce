# Refine Request — Rubric

## Baseline expectation

A model without the intake discipline treats all incoming requests the same
way: it either starts work immediately on an underspecified request (guessing
at scope and authority), or it asks a generic barrage of clarifying questions —
including on requests that are already fully specified, where any question is
pure friction. It does not name which specific missing element a question
closes, and it silently jams unfamiliar request shapes into the nearest
familiar bucket.

## Must-pass behaviors

1. **must-pass** — For the fully specified request, asks **zero** questions and
   proceeds (or states it would proceed) directly.
2. **must-pass** — Every question asked names the specific gap it closes —
   deliverable, scope, done-condition, or authority — and no question is asked
   that maps to none of the four.
3. **must-pass** — Questions for a single request are delivered as one numbered
   round, each with a recommended answer the human can accept wholesale.
4. **must-pass** — An immaterial gap (any reasonable answer leads to the same
   first action) is closed with a stated default assumption, not a question.
5. **must-pass** — The request fitting no known shape is explicitly identified
   as unclassified, the generic four-check scan is still run on it, and the
   novel shape is flagged for taxonomy review rather than silently force-fit.

## Advisory behaviors

6. **advisory** — Project-scale gapped requests (answers would themselves
   branch into further decisions) are routed to the deep interviewing
   discipline rather than handled in one round.
