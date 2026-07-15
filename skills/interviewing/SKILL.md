---
name: interviewing
description: Interview the human about a design one decision at a time until shared understanding is confirmed — facts from the codebase, decisions from the human. Use when a request is fuzzy, before writing any spec or plan, or when the user asks to be grilled about a design.
---

# Interviewing

Job: turn a fuzzy request into a confirmed shared understanding before any spec
or plan is written. Use at the start of standard/large design work.

## Method

- Walk each branch of the design tree, resolving dependencies between decisions
  one by one — earlier answers reshape later questions, so order matters.
- Ask exactly one question at a time and wait for the answer. Multiple questions
  at once is bewildering and gets shallow answers.
- With every question, state your recommended answer and why. A recommendation
  gives the human something concrete to push against.
- First, check scope: if the request spans several independent subsystems, say so and split it — one interview and one spec per subsystem — before refining any detail.

## Facts vs decisions

- A **fact** — anything already true in the codebase, configs, docs, or history —
  gets looked up, never asked. Asking the human for a fact you could have read
  wastes their attention and erodes trust in the questions that matter.
- A **decision** — a tradeoff, a preference, a scope call, a priority — is the
  human's alone. Put each one to them individually and wait for the answer.
- When the human defers ("you decide", "I don't know", "whatever's standard"),
  that is an answer: propose the option you'd pick with its one-line reason,
  record it as a provisional decision they can override, and move on — don't
  re-ask. If a decision genuinely can't be made yet (needs data you don't have),
  record it as an explicit open question with a default and proceed; a stalled
  corner is surfaced, not looped on.

## The gate

Do not proceed to designing until all four corners are pinned down:

1. **Purpose** — what this is for, in the human's words.
2. **Non-goals** — what it deliberately will not do.
3. **Constraints** — what must be respected (tooling, policy, compatibility).
4. **Success criteria** — how everyone will know it worked.

When you believe understanding is shared, play it back: a short summary of what
will be built and what won't. Ask for explicit confirmation, and only then move
on to the spec.

Read `CONTEXT.md` (if it exists) so names match the project's domain language; respect ADRs in the area you're touching.
