# Dissent: a judged pair

Scenario: panel reviewing a caching design whose consensus concern is cache
invalidation on write.

**Vacuous (fails):**
"Strongest objection: I share the concern about cache invalidation on write —
this needs more thought." — restates the room; adds no framework-specific
stake; "needs more thought" commits to nothing.

**Genuine (passes):**
"Strongest objection: this design's TTL of 300s makes the *read-after-write*
guarantee unstatable — from my consistency-model lens, either the spec commits
to bounded staleness (state the bound) or the checkout flow must bypass the
cache; it currently promises both freshness and performance without choosing."
— framework-specific, names the exact defect, forces a decision.
