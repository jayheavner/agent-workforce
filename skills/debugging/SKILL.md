---
name: debugging
description: Diagnosis loop for real bugs — build a red-capable feedback loop first, minimise the repro, rank falsifiable hypotheses, instrument one variable at a time, fix with a regression test, clean up. Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes.
---

# Debugging

Job: a discipline for bugs that resist the first look — including defects a
verifier or reviewer bounced back. Skip a phase only when you can say why.

## Phase 1 — Build a feedback loop

This is the skill; everything after is mechanical. A tight pass/fail signal that
goes red on *this* bug means bisection, hypotheses, and instrumentation all have
something to consume. Without one, no amount of reading code will save you.

Ways to construct one, roughly in order: a failing test at whatever seam reaches
the bug; a curl/HTTP script against a dev server; a CLI run with a fixture input
diffed against known-good output; a replayed captured payload; a throwaway
harness exercising just the bug's code path; a 1000-random-input loop for
"sometimes wrong" bugs; a bisection harness over commits/states; a differential
run of old-vs-new on the same input.

For non-deterministic bugs the goal is a **higher reproduction rate**, not a
clean repro: loop the trigger, add stress, narrow timing. A 50% flake is
debuggable; 1% is not.

Once you have *a* loop, tighten it: faster (skip unrelated init), sharper
(assert the exact symptom, not "didn't crash"), more deterministic (pin time,
seed RNG, isolate filesystem).

**Completion criterion:** one command — a script path, a test invocation, a curl
— that you have already run at least once (keep the invocation and its output),
and that is: **red-capable** (asserts the exact symptom, so it goes red on this
bug and green when fixed), **deterministic** (same verdict every run, or a
pinned high repro rate), **fast** (seconds), and **agent-runnable** (no human in
the loop). Reading code to build a theory before this command exists is the
exact failure this discipline prevents. If you genuinely cannot build one, stop
and report what you tried and what access or artifact would unblock you.

## Phase 2 — Reproduce and minimise

Run the loop; watch it go red with the failure that was actually reported — a
nearby different failure means the wrong bug and the wrong fix. Then shrink to
the smallest scenario that still goes red: cut inputs, callers, config, and
steps one at a time, re-running after each cut. Done when every remaining
element is load-bearing. The minimal repro shrinks the hypothesis space and
becomes the regression test.

## Phase 3 — Hypothesise

Write 3–5 ranked hypotheses before testing any — a single hypothesis anchors you
to the first plausible idea. Each must be falsifiable: "if X is the cause, then
changing Y makes the bug disappear". A hypothesis with no testable prediction is
a vibe; sharpen or discard it. Include the ranked list in your report. Show the
ranked list to the human when one is present — they re-rank instantly ("we just
deployed a change to #3"). Cheap checkpoint; don't block on it.

## Phase 4 — Instrument

Each probe maps to one prediction from Phase 3; change one variable at a time.
Prefer a debugger or REPL breakpoint over logs; prefer targeted logs at the
boundaries that distinguish hypotheses over "log everything and grep". Tag every
debug log with one unique prefix (e.g. `[DEBUG-a4f2]`) so cleanup is a single
grep. For performance bugs, logs are usually wrong: measure a baseline first,
then bisect. If three fixes have failed, stop — 3+ failed fixes is an
architectural problem; question the pattern instead of attempting fix #4.

## Phase 5 — Fix + regression test

Resolve `policy:workspace-isolation` from the project policy and state the
resolved value and its source — project policy / user policy / judgment
default — before the fix touches any file. Where no policy defines it: open a
discrete worktree inside the project folder.

Write the regression test before the fix, at a seam where the test exercises the
real bug pattern as it occurred. If the only available seam is too shallow to
replicate the triggering chain, a test there is false confidence — the missing
seam is itself a finding; record it. Then: failing test → fix → passing test →
re-run the Phase 1 loop against the original, un-minimised scenario.

## Phase 6 — Cleanup

Before declaring done: original repro no longer reproduces; regression test
passes (or the seam gap is documented); every tagged instrumentation line is
removed (grep the prefix); throwaway harnesses deleted or clearly parked;
commit the fix — not left staged — with the confirmed hypothesis stated in
the commit message so the next debugger learns.

See `references/condition-based-waiting.md` for flaky-timing bugs and
`references/defense-in-depth.md` for after the root cause.
