---
name: refine-request
description: Assess an incoming request before work starts — a four-check gap scan (deliverable, scope, done-condition, authority) that asks only about what is materially missing, so complete requests proceed untouched and lazy prompts get one sharp round of questions. Use at intake of any new request, when a prompt seems underspecified, or when deciding whether clarification is needed at all. For deep design elicitation on project-scale work, defer to interviewing and the iv-* family.
requires: [interviewing]
---

# Refine Request

Job: decide how much refinement an incoming request needs — often none — and
do exactly that much before any work starts. Refinement effort is earned by
named gaps, never applied by ritual.

## The four-check gap scan

From the prompt alone (plus anything you can look up), try to state:

1. **Deliverable** — what artifact or outcome the request produces.
2. **Scope** — where the work may touch, and where it must not.
3. **Done-condition** — how everyone will know it succeeded.
4. **Authority** — assess-only vs act, and how far action may go
   (report / fix / commit / ship).

Each check you cannot state, or can only guess at, is a named gap. Zero gaps
means zero questions: proceed. Never ask a question that maps to none of the
four — "aligning" on an already-complete request is friction, not diligence.

## Materiality filter

A gap earns a question only if closing it would change the work. If every
reasonable answer leads to the same first action, take the strongest default,
state the assumption in one line, and proceed — the human can veto a stated
assumption far more cheaply than they can answer a needless question.

## Facts are yours, decisions are theirs

Anything discoverable — in the repo, configs, tickets, history, or tools — is
looked up, never asked. Only genuine decisions (tradeoffs, scope calls,
priorities) go to the human. This is the same contract interviewing states;
it binds here too.

## Asking: one frontier round

Deliver all material questions for a request as a single numbered round, each
with your recommended answer, so a busy human can reply "all recommendations"
and move on. Format:

> **Q1 — <gap it closes>**: <question>
> ➡ <recommended answer and one-line reason>

Every question asked at intake uses this format — including a scoping
question that precedes a handoff. If the answers to this round would
themselves branch into further rounds of decisions, the request is
project-scale: stop grilling and hand off to `interviewing` (or the iv-*
family when a spec is the goal).

## Shapes are advisory, never a gate

`references/shapes.md` catalogs recurring request shapes and the gap-scan
defaults each carries (a runbook brings its own done-condition; a debug
request defaults to assess-only). Matching a shape only pre-fills defaults —
the scan itself is shape-independent. A request matching no shape is handled
by running the scan raw; say in one line that it is unclassified so it never
silently inherits the nearest shape's wrong defaults, and flag the novel
shape at closeout as a taxonomy candidate for human review.

## Routing summary

- **No material gaps** → proceed, stating any defaulted assumptions.
- **Material gaps, answers won't branch** → one frontier round, then proceed.
- **Answers would branch** → hand off to `interviewing` / iv-*.

Read `CONTEXT.md` (if it exists) so names match the project's domain
language; respect ADRs in the area touched.
