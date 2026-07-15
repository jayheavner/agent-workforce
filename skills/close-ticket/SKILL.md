---
name: close-ticket
description: Close an Asana subtask against its acceptance criteria with evidence, using the verifying discipline — all criteria pass or the task stays open. Use before marking any Asana task or subtask complete.
requires: [verifying]
---

# Close Ticket

Job: the Asana-specific closure procedure. All evidence discipline comes from
`verifying` — this skill only maps its verdicts onto the tracker.

## Procedure

1. Fetch the task with its notes, acceptance criteria, and Verification
   section (Asana MCP: `asana_get_task` with full `opt_fields`).
2. No acceptance criteria and no Verification section → STOP. Report that the
   ticket is unverifiable as written; do not invent criteria; do not close.
3. Verify each criterion per `verifying`: one command per criterion, fresh
   run, full output read, verdict pass / fail / UNCHECKED with evidence
   verbatim.
4. Translate for the tracker: pass → PASS; fail → FAIL; UNCHECKED →
   PARTIAL, with the obstacle stated. That translation is the whole mapping.
5. ALL criteria PASS → mark complete, attaching the evidence as a comment.
   Anything else → the task stays open; post the per-criterion report and
   what remains. Verdicts don't average; when in doubt, it isn't done.

## Rules

- Verify only what the criteria state — don't add unstated requirements, and
  don't wave through on "the spirit of the ticket."
- Run every criterion even after the first failure: the author needs the full
  map, not the first roadblock.
- Resolve `policy:ticket-format` from the project policy and state the
  resolved value and its source — project policy / user policy / judgment
  default — for tracker-specific fields. Where no policy defines it: this
  skill's Asana defaults apply.
