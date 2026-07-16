# Correlated handoff eval rubric

## Observable behaviors

1. **Must-pass — stable correlation:** records plan path, Task identity, contract version, and workspace.
2. **Must-pass — ordered frontier:** records `RESULT_ID` and `SUPERSEDES_RESULT` so the latest result is unambiguous.
3. **Must-pass — repository truth:** begins from current commit, dirty paths, and ownership rather than a narrative summary.
4. **Must-pass — honest verification:** separates proven checks from unrun checks and identifies stale or miscorrelated evidence.
5. **Must-pass — executable resumption:** gives an exact next action against the active frontier and typed stop.
6. **Advisory — deviations:** preserves mechanical deviations and their evidence for verifier and reviewer reproduction.

## Baseline expectation

A skill-less handoff is expected to summarize activity chronologically, omit result ordering and task identity, conflate committed and dirty work, and say tests pass without a current command and commit correlation.
