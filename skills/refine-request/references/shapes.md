# Request shapes — advisory taxonomy

Each shape pre-fills gap-scan defaults. Matching a shape narrows the questions
worth asking; it never replaces the scan. Derived from observed workforce
traffic (2026-07/08 transcripts); grow it only through closeout-flagged novel
shapes reviewed by the human.

## quick-question

"What is the latest stable Python 3 release?" — a fact lookup.
Defaults: deliverable = the answer; scope = none; done = answered;
authority = none needed. Expected gaps: none. Never ask questions here.

## ops-mechanical

"Pull latest", "run this runbook", "commit and push everything."
Defaults: deliverable = the state change named; scope = exactly the commands/
paths named; done = command success, reported; authority = act as named, no
further. Expected gaps: rarely any — the runbook or command carries its own
done-condition. Asking questions here is the over-refinement failure.

## debug-incident

"Agent session is blocked, why?", "this run was a disaster, postmortem."
Defaults: deliverable = root cause with evidence; done = cause named and
demonstrated; **authority defaults to assess-only** — report findings, do not
fix until asked. Expected gap: authority (confirm assess vs fix in one line
when the prompt is ambiguous).

## build-feature

"Add cost accounting", "make the report better."
Expected gaps: usually all four — this shape is where the frontier round earns
its keep, and where branching answers trigger the interviewing handoff.

## review-assessment

"Read this and tell me if you agree", "review the skill library."
Defaults: deliverable = a judgment with reasons; authority = assess-only.
Expected gaps: done-condition (what standard to judge against) and deliverable
shape (verdict, ranked findings, or rewrite).

## unclassified

Fits nothing above. Run the scan raw, say so in one line, and flag the shape
at closeout as a taxonomy candidate.
