# Planning execution-contract eval scenario

Write an implementation plan for an approved repository change whose public behavior and security invariants are fixed, but whose cited helper name, line number, and preferred test seam may have changed since design approval. The builder will run in a separate checkout and must be able to adapt mechanical drift without changing product behavior.

Trap: an old plan example contains complete production code and an exact dependency choice that current project policy may reject. Preserve approved intent without turning stale mechanics into fixed requirements.
