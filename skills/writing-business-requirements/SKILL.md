---
name: writing-business-requirements
description: Use when writing or reviewing business requirements documents following industry standards (BABOK v3, IEEE 830). Use when drafting new functional requirements, fixing requirements defects found in an audit, or extracting business needs from mixed documentation.
requires: [auditing-requirements]
---

# Writing Business Requirements

Job: write requirements that state WHAT capability users need, never HOW
the system provides it — atomic, testable, unambiguous, and observable,
each with Given-When-Then acceptance criteria. Pairs with
`auditing-requirements`, which enforces this discipline after authoring.

## Document structure

Business context (stakeholders, domain, objectives) is written ONCE at the
document level, never repeated inside individual requirements. Each
functional requirement then follows the `FR-n` template in
`references/templates.md`: identifier, priority, source, status, the
requirement statement, rationale, dependencies, acceptance criteria, and
verification method.

## Core principles

Every requirement must satisfy all four:

**Atomic** — one capability per requirement, not a compound sentence.
- Wrong: "The system shall classify documents and display results and log errors"
- Right: split into three requirements, one capability each (FR-001, FR-002, FR-003)

**Testable** — verifiable through inspection, test, analysis, or demonstration.
- Wrong: "The system shall be fast"
- Right: "The system shall display results within 5 seconds of upload completion"

**Unambiguous** — only one interpretation possible.
- Wrong: "The system shall handle errors gracefully"
- Right: "When classification fails, the system shall continue processing
  remaining documents and display error details to the reviewer"

**Observable** — external behavior, not internal implementation.
- Wrong: "The system shall use try-except blocks to catch exceptions"
- Right: "When errors occur, the system shall display error messages to reviewers"

## Acceptance criteria (Given-When-Then)

Every requirement carries a minimum of 2-3 acceptance criteria:

- **Given** the precondition or system state beforehand
- **When** the action or trigger occurs
- **Then** the observable, verifiable outcome

Each criterion must independently be testable, unambiguous, and observable
— the same three principles above, applied at the criterion level, not just
the requirement as a whole.

## Prohibited language

Never state return values/types, exception-handling constructs, function or
API calls, data structures, control-flow keywords, named technical
mechanisms, or unverified performance claims — say what the user
experiences instead ("system displays", "reviewer receives", "user sees").
The full wrong-phrasing -> correct-phrasing translation table, by category,
lives once in `auditing-requirements/references/patterns.md` — consult it
for edge cases rather than guessing; `auditing-requirements` re-applies the
same table to enforce this after you write.

## Scope boundaries

Business requirements hold: functional capabilities, user workflows,
information visibility, decision-making capability, business rules, and
data inputs/outputs from the user's perspective.

They do NOT hold implementation detail, technology choices, architecture
rationale, or test procedures. When you find one of these while drafting,
don't delete it — relocate it. The destination for each category (coding
rules, architecture decisions, setup docs, test docs) is the same mapping
`auditing-requirements` audits against: see
`../auditing-requirements/references/patterns.md`.

## Identifiers, priority, and citations

`FR-n` sequential numbering, MoSCoW priority (Must/Should/Could/Won't Have),
status values, and BABOK v3 / IEEE 830 / ISO 29148 citation conventions are
craft defaults, not policy — no `policy:` key covers requirements-document
citation format. `references/templates.md` shows the current values in use;
adjust them per project convention.

## Related skills

`auditing-requirements` — run after authoring to detect violations and get
destination recommendations for anything misplaced.
