---
name: growing-the-team
description: Create a new skill or agent for the workforce when a task exposes a capability gap — draft it in the workforce repo marked provisional, use it immediately for the live task, and disclose it at closeout for human review and possible upstreaming. Use when the practitioner test fires (a practitioner of the field would reject work that merely satisfies the spec), when a task shape recurs that no specialist fits, or when the orchestrator or architect names a capability gap.
---

# Growing the team

The team is self-extending: a capability gap met mid-task produces the missing capability, not
a stall and not silent winging-it. The loop is create → use → disclose. Human review happens
after delivery, on a working draft with evidence from real use — never as a gate before the
task can proceed.

## When this fires

- **Domain gap:** the practitioner test fires and no `domain-<field>` or covering skill exists.
  A field's norms (accounting, payroll, actuarial pricing, logistics, medical billing…) are
  load-bearing for correctness and nobody on the team knows them.
- **Procedure gap:** the team keeps solving the same shaped problem ad hoc — the third ad-hoc
  solution of one shape is a skill waiting to be written.
- **Role gap:** work recurs that no specialist's identity fits (wrong tools, wrong model tier,
  wrong permission posture), and stretching an existing role would break its boundaries.

Hard is never a gap. Difficult work inside an existing role's charter is just work.

## Drafting a skill

1. Gather grounding first. For a domain gap, researcher-sourced constraints (labeled
   *uncertified*) are the input — never draft domain norms from memory.
2. Invoke `writing-skills` and follow its authoring standard: job stated in the first three
   lines, routing description that says when to use it, knowledge not compliance-rhetoric, no
   org-policy values in the body (use `policy:` keys where policy applies).
3. Write it to `skills/<name>/SKILL.md` in the workforce repo, with `provenance: provisional`
   in the frontmatter and a one-line note naming the task that birthed it.
4. Use it immediately: carry its constraints into the live task's plan explicitly (the builder
   cannot load skills mid-dispatch — the plan is the carrier).

## Drafting an agent

Only for a confirmed role gap — a skill plus an existing role covers most gaps. Copy the
closest existing definition in `agents/` and change what the gap demands: identity, tools
(smallest set that does the job), model and effort (cheapest tier that is honest about the
work), permission posture (mutating roles carry the secrets + audit hooks; read-only roles get
no Write/Edit), and a description that says when the orchestrator should dispatch it. Mark the
body's first line `Provisional agent — created <date> for <task>; awaiting human review.`

A new agent is dispatchable only after ALL THREE touchpoints change, plus an install and a new
session — the drift test pins them to each other:

1. `agents/<name>.md` — the definition itself.
2. `agents/orchestrator.md` frontmatter `tools:` — add `Agent(<name>)`.
3. `hooks/agent-team-dispatch-guard.sh` `VALID_SPECIALISTS` — add `<name>`, or the guard
   hard-blocks the dispatch.

Note in the disclosure that the agent activates next session, and which touchpoints changed.

## Disclosure — the non-negotiable step

Every closeout of a task that grew the team says so: what was created, the path, why the gap
was real, what evidence its first use produced, and that it awaits review. Provisional drafts
are candidates for upstreaming to the shared skills framework (`jayheavner/skills`) when they
are generic; consumer-specific ones stay here and lose the provisional marker when the human
accepts them. A draft the human rejects is deleted, and the rejection reason recorded in the
status note — the next session must not re-create it from scratch unaware.
