---
name: write-ticket
description: Create well-structured Asana tickets and subtasks using separation of concerns, objective acceptance criteria, and correct dependency sequencing. Use when drafting a new ticket, decomposing work into subtasks, or setting task dependencies for tracked work.
---

# Write Ticket

Job: turn a piece of work into a ticket structure that can be executed and
verified without mid-work guessing — one concern per subtask, objective
criteria, correct sequencing.

## Decomposition

Apply separation of concerns: each subtask addresses ONE well-defined,
independently testable responsibility. Don't mix concerns (e.g. "fix bug AND
refactor AND add feature") into a single subtask, and don't flatten a subtask
list into an inline checklist inside a task description — discrete subtasks
give independent assignment, status, and dependency tracking that a
checklist can't.

Size each subtask to roughly 2-5 acceptance criteria: not so large it exceeds
about a week of focused work, not so small (~15 minutes) that ticket
overhead exceeds the work itself.

## Parent vs. subtask

The parent task states WHAT and WHY, never HOW: objective, business context,
and success criteria only — no step-by-step instructions (those belong in
subtasks). Each subtask states HOW: the specific action, its acceptance
criteria, and how completion is verified.

Asana's vendor best practice is subtasks one layer deep (parent -> subtasks,
no sub-subtasks): deeper nesting loses dependency tracking and status
visibility, so decompose further at ticket-creation time instead of nesting
a subtask under a subtask.

Templates for both -> `references/templates.md`.

## Acceptance criteria

Every criterion must be objective and verifiable — "tests pass", "returns
HTTP 429", "docs contain examples" — never "looks good" or "works well".
Subjective criteria can't be verified, so they can't gate completion.

**Unit tests can gate completion; integration tests cannot.** Integration
tests are often slow, external, or costly to run repeatedly — treat them as
optional validation, never as a mandatory completion criterion.

## Dependencies

Set explicit BLOCKS/BLOCKED BY relationships whenever order genuinely
matters — most importantly, tests BLOCK implementation (a subtask that
writes implementation code is blocked by the subtask that writes its
tests). Don't add a dependency where order is only a preference;
unnecessary sequencing kills parallelism.

## Skills to use

Every subtask names the skills mandatory for its task type. Task-type ->
discipline mappings live in `references/task-type-map.md` — consumers edit
that file to match the skill names actually installed in their project.

## Draft before creating

Show the proposed parent + subtask structure, with dependencies, to the
user before creating anything. Once confirmed: create the parent, then
subtasks parented to it, then dependencies between them, in that order.

## Ticket format policy

Resolve `policy:ticket-format` from the project policy and state the
resolved value and its source — project policy / user policy / judgment
default — before drafting; it may override field names or add
project-specific sections. Where no policy defines it: use
`references/templates.md` as-is.
