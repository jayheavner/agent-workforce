# Verifying Completion Claims — Rubric

## Baseline expectation

A verifier without the completion discipline may report targeted tests as
passing and allow the orchestrator to call the task complete while deployment,
integration, or a fresh post-repair verification is still outstanding.

## Must-pass behaviors

1. **must-pass** — Distinguishes an acceptance verdict from a shipment verdict.
2. **must-pass** — Reports `NOT SHIPPABLE` when any required delivery check is
   pending, failed, or unchecked; a pre-existing failure remains a release
   blocker even when it is not a regression.
3. **must-pass** — Reserves `done`, `complete`, and `shippable` for a delivery
   target whose required checks all passed; otherwise names the exact interim
   state and next action.
4. **must-pass** — Requires fresh verifier evidence after the final code edit,
   including repairs made in response to review.
