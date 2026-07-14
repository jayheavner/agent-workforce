---
name: review-ticket
description: Review an Asana ticket for ownership, validity, and true scope before starting work on it — the mandatory reconnaissance step before any tracked work begins. Use when given a ticket ID or URL, asked "what should I work on?", or before starting any Asana-tracked work.
requires: [write-ticket]
---

# Review Ticket

Job: scout the terrain before acting — is this ticket mine to take, still
valid, and correctly scoped — so the user gets an informed go/no-go instead
of a mid-flight surprise.

## Reconnaissance before acting

Fetch the full task (notes, assignee, status, dependencies, subtasks,
parent) before doing anything else. Don't start implementation, and don't
skip straight to "what does the ticket say to do" — the fetch and the
analysis below come first, every time.

## Ownership check

If the task is already assigned to someone else, stop and report to the
user — do not proceed with the work unless the user explicitly instructs a
takeover of this specific ticket. Unassigned tasks, or tasks assigned to the
current session, can proceed.

## Parent/subtask context

Reviewing a subtask -> fetch and read its parent (the objective, the WHY,
any cross-subtask constraints). Reviewing a parent -> fetch and read all its
subtasks (the actual decomposition and current status). Never review one
without the other.

## Scope analysis

Check whether the ticket's stated scope matches implementation reality:
search the codebase for related work, similar patterns, and anything the
ticket doesn't mention that the change will actually touch.

Recommend splitting the ticket (dispatch or hand off to `write-ticket`) when
any of:
- it mixes multiple concerns (e.g. "fix bug AND refactor AND add feature")
- it needs infrastructure/config changes before the described work can start
- there's a real sequential dependency (spec -> tests -> implementation) the
  ticket doesn't reflect
- the work is too large for one focused session
- different parts need different skills or expertise

## Validate required skills

If the task has a "Skills to Use" section, confirm every named skill
actually resolves — exists, correctly spelled — before recommending
execution proceed. An unresolved skill name is a blocker to flag, not a typo
to guess past silently.

## Report and next step

Give the user validity, blockers, the scope assessment (including any
decomposition recommendation), the required-skills check, and one clear
recommended next step: proceed, clarify, split, defer on a blocker, or close
as invalid. Template -> `references/report-templates.md`.

## Ticket format policy

Resolve `policy:ticket-format` from the project policy and state the
resolved value and its source — project policy / user policy / judgment
default — before presenting the report. Where no policy defines it: use
`references/report-templates.md` as-is.
