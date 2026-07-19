---
name: planning
description: Write implementation plans an engineer with zero context can execute — exact files, complete code in every step, bite-sized TDD tasks, checkbox tracking, self-review. Use when turning an approved spec into tasks, before touching code.
---

# Planning

Job: turn an approved spec into a plan a skilled engineer with zero context for
this codebase — and questionable taste — can execute without asking questions.
Save plans where the project keeps them (default: `plans/YYYY-MM-DD-<feature>.md`).

## Before writing tasks

- **Spec completeness gate:** a plan can only be as complete as its spec. Before
  planning, check the spec pins down what the tasks will need — the interfaces,
  the acceptance criteria, the decisions a task would otherwise have to invent.
  Where it doesn't, stop and get it resolved (via `interviewing`) rather than
  papering the hole with a placeholder or a guessed decision — an
  invented-decision task is worse than an admitted gap. If a small gap can't be
  closed now, name it in the plan header as an open question with the assumption
  the tasks proceed on, so the executor sees the seam.
- **Scope:** if the spec spans several independent subsystems, write one plan per
  subsystem; each plan must produce working, testable software on its own.
- **File structure first:** map every file to create or modify and give each one
  clear responsibility. Prefer small, focused files; follow the codebase's
  existing patterns rather than restructuring unilaterally.

## Plan header

Every plan opens with: Goal (one sentence), Architecture (2–3 sentences),
Tech Stack, and a **Global Constraints** section quoting the spec's project-wide
requirements verbatim — version floors, naming rules, platform requirements —
one line each. Always include the resolved workspace-isolation policy: resolve
`policy:workspace-isolation` from the project policy and state the resolved
value and its source — project policy / user policy / judgment default — and
quote it verbatim in the header. Where no policy defines it: each code-writing
task gets its own discrete git worktree, created only inside the project
folder. Every task implicitly includes that section.

## Tasks

A task is the smallest unit that carries its own test cycle and is worth a fresh
reviewer's gate: fold setup and scaffolding into the task whose deliverable needs
them; split only where a reviewer could reject one task while approving its
neighbor. Each task carries:

- **Files:** exact paths — Create / Modify (with line ranges) / Test.
- **Interfaces:** what it consumes from earlier tasks and produces for later
  ones, with exact names and signatures. A task's implementer may see only their
  own task; this block is how they learn what neighbors expect.
- **Steps:** checkboxed, one action each (2–5 minutes):
  1. Write the failing test — show the actual test code.
  2. Run it — exact command, expected failure message.
  3. Write the minimal implementation — show the actual code.
  4. Run again — exact command, expected pass.
  5. Commit — exact `git` command with message.

## No placeholders

These are plan failures, never written: "TBD", "TODO", "implement later",
"add appropriate error handling", "write tests for the above" without test code,
"similar to Task N" (repeat the code — tasks may be read out of order), steps
that describe without showing, and references to types or functions no task
defines.

## Dependencies and security (absorbed from plan-review)

- Resolve `policy:dependency-freshness` from the project policy and state the
  resolved value and its source — project policy / user policy / judgment
  default — before any task pins a version. Where no policy defines it:
  versions are verified current by search and pinned exactly, never recalled
  from memory.
- Every plan carries one pre-implementation security pass: no secrets in code
  or logs, inputs validated at boundaries, errors sanitized before display.

## Self-review

After writing the full plan, check it against the spec with fresh eyes:
1. **Coverage** — every spec requirement maps to a task; list gaps.
2. **Placeholder scan** — search for the patterns above.
3. **Consistency** — names, types, and signatures in later tasks match their
   definitions in earlier tasks.

Fix findings inline and move on. DRY. YAGNI. TDD. Frequent commits.
