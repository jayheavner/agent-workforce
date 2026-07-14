---
name: tdd
description: The red→green loop and what makes it produce tests worth keeping — seams, anti-patterns (tautological, implementation-coupled, horizontal slicing), rules of the loop. Use when implementing any feature or bugfix, before writing implementation code.
---

# Test-Driven Development

Resolve `policy:workspace-isolation` and state value + source before the first
file is touched. Read `CONTEXT.md` (if it exists) so test names match the
project's domain language.

TDD is the red → green loop. This skill is what makes that loop produce tests
worth keeping: what a good test is, where tests go, the anti-patterns, and the
rules of the loop. It teaches technique. Resolve `policy:coverage` from the
project policy and state the resolved value and its source — project policy /
user policy / judgment default — before the first cycle. Where no policy
defines it: no numeric gate; TDD always.

## What a good test is

Tests verify behavior through public interfaces, not implementation details.
Code can change entirely; tests shouldn't. A good test reads like a
specification — "user can checkout with valid cart" says exactly what capability
exists — and survives refactors because it doesn't care about internal structure.

## Seams — where tests go

A **seam** is the public boundary you test at: the interface where you observe
behavior without reaching inside. Tests live at seams, never against internals.

Test only at agreed seams — for plan-driven work, the seams are the interfaces
the plan names. You can't test everything; agreeing seams up front is how effort
lands on critical paths and complex logic instead of every edge. If a behavior
you must test has no seam in the plan, report it — don't invent one silently.

Legacy code often has no seam yet: logic buried in a function that also does I/O,
with nothing testable to call. Don't skip the test and don't test through the
I/O. Make the seam first with a **behavior-preserving** refactor — extract the
logic into a callable unit, no logic change — pin it with a characterization test
that captures what the code does today (bug-for-bug), and only then start the
red→green loop for the change. Cutting the seam is itself a step, not a detour.

## Anti-patterns

- **Implementation-coupled** — mocks internal collaborators, tests private
  methods, or verifies through a side channel (querying the database instead of
  the interface). The tell: the test breaks on refactor though behavior didn't.
- **Tautological** — the assertion recomputes the expected value the way the
  code does (`expect(add(a, b)).toBe(a + b)`, a hand-derived snapshot, a
  constant asserted against itself), so it passes by construction and can never
  disagree with the code. Expected values come from an independent source of
  truth: a known-good literal, a worked example, the spec.
- **Horizontal slicing** — writing all the tests first, then all the
  implementation. Bulk tests verify *imagined* behavior: they encode the shape
  of things instead of user-facing behavior and go insensitive to real changes.
  Work in **vertical slices**: one test → one implementation → repeat, each test
  a tracer bullet responding to what the last cycle taught you.

## Rules of the loop

- **Red before green.** Write the failing test first and watch it fail — a test
  you never saw red proves nothing. Report the one concrete failure actually
  observed from running it, not a predicted or hedged failure mode ("fails
  with a NameError or AttributeError" is not red, it's a guess). Then only
  enough code to pass it.
- **One slice at a time.** One seam, one test, one minimal implementation per
  cycle. No speculative features, no anticipating future tests.
- **Refactoring is not part of the loop.** Refactor on green as its own step —
  never while a test is red.

## When stuck

- Test too complicated → the design is too complicated. Simplify the interface.
- Must mock everything → the code is too coupled. Inject dependencies.
- Hard to test = hard to use.

See `references/mocking.md` (where mocks belong) and
`references/test-examples.md` (good/bad pairs).
