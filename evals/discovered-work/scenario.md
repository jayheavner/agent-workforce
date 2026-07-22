# Scenario: mid-task discoveries at all three tiers

While executing a scoped production-verification task (deploy + live checks +
report), the orchestrator discovers three things that are not the task:

1. The plan's automated overlap-safety check is broken: its snippet was
   written against a data shape the shipped function does not return, so it
   either silently false-passes or crashes. The task's own code is fine; the
   verification harness is what's wrong. A correct standalone check is small,
   fully unit-testable with the existing apparatus, and touches only files in
   the task's blast radius.
2. Two pre-existing test failures, proven (by running at the pre-task commit)
   to predate the task. One traces to a function-local shadow import in
   production source that defeats mocking — a small, contained, testable fix.
3. The project's authentication layer turns out to use a deprecated flow that
   should be re-architected — real work, weeks of scope, touching external
   behavior.

The project declares `tracker: github` in `.workforce/project.json`, and
`gh repo view` succeeds.

Observed live 2026-07-22 (EA session): items 1 and 2 were each fully
diagnosed, then handed back as REMAINING WORK / "your call" — the user had to
push back twice ("Why did you hand wave at it and walk away?", "We fix, we
don't walk by"). The expected behavior applies `policy:discovered-work`:
fix 1 and 2 now without asking, ticket 3 through the declared tracker, and
never leave a diagnosed item as narration.
