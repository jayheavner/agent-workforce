---
name: handing-off
description: Write a handoff brief that lets a fresh session resume mid-task work without re-derivation — exact next actions, verification state split into proven vs unrun, dirty-tree disclosure, decisions with their why. Use when ending a session mid-task, when asked to "hand off", "wrap up for the day", or "write up where we are", or before context runs out on unfinished work.
---

# Handing Off

Job: get the next session productive in the first minute. A handoff is
written for a reader with zero context from this session — what they need
is the work's frontier, not its history.

## The frontier, not the log

Start from the working tree, not the commit log: `git status` and the
diff are the actual state of the work. Uncommitted changes are the most
important thing in the brief — name each one, its intent, and how far it
got (a half-wired call site with a TODO is frontier; describe it as
precisely as a finished one). A handoff that only describes committed
work hands off the wrong thing.

## Next actions, executable

The first section a reader acts on: the immediate next step as an exact
action — the file to edit and what to change, the command to run, the
test to make pass. "Continue the retry integration" is a topic;
"convert the remaining call site in `handler.py:42` to `retry_call()`,
then implement the dead-letter TODO above it" is a next action. Order
them; one clear first step beats five parallel maybes.

## Verification state, split honestly

Report what is proven and what is merely believed, per `verifying`:
each proven claim carries the command that proved it and when it last
ran; everything else is listed as unverified — including suites that
exist but were not run this session, with whatever precondition they
need. "Tests pass" without naming which tier ran is the classic handoff
lie; the next session inherits a false green.

## Decisions with their why

Any choice the next session could plausibly revisit gets its rationale
recorded — especially decisions that depend on dead ends this session
already explored ("backoff over queue: the queue spike failed on
ordering"). A decision recorded without its why will be re-litigated or
silently reversed. Link the decision log or ADR where one exists rather
than restating it.

## Landmines

List the traps this session hit that cost time and will cost the next
session the same: flaky services and their restart ritual, misleading
error messages, files that look relevant but aren't. One line each.

Keep the brief delta-oriented — what changed, what's next, what to
watch — and put it where the next session will look: the project's
convention if it has one, otherwise a dated file the final message
points at. Read `CONTEXT.md` if present so names match the project's
domain language.
