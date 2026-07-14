---
name: auditing-requirements
description: Audit a business-requirements document for standards violations — implementation detail, technology specifics, architecture rationale, or test procedures that belong elsewhere — and report each with severity and a recommended destination. Use after authoring requirements, before requirements code review, during a requirements refactor, or when onboarding to the requirements standard.
---

# Auditing Requirements

Job: read a requirements document and flag content that violates the
WHAT-not-HOW standard `writing-business-requirements` defines, then report
each violation with location, category, severity, and destination. You
perform this audit by hand — there is no automated pipeline and no code to
run. The judgment is yours; the report records which pattern categories you
applied so a human can spot-check the work.

## Procedure

1. Read the target document in full before judging any single line. Note
   section headings and line ranges so the report can cite precise
   locations; preserve requirement identifiers (e.g. `FR-003`) exactly.
2. Apply the 4-category catalog in `references/patterns.md` against every
   requirement statement and its rationale: Implementation Details,
   Technology Specifics, Architecture Rationale, Test Plans and Procedures.
   Apply the false-positive rules below before flagging anything.
3. Assign a destination per the mapping in `references/patterns.md`. The
   destination is a recommendation for the human, not an action you take —
   this skill reports; it does not move or rewrite content.
4. Write the violation report: which pattern categories you applied, then
   each violation (location, category, severity, found text, why, suggested
   rewrite, recommended destination), then a summary. Format in
   `references/patterns.md`.

## False positives — do NOT flag

- Implementation language inside a fenced code block.
- A clearly-labelled example or illustration (describing, not prescribing).
- An attributed quote ("the developer noted: '...'").
- A cross-reference that only points elsewhere.
- Content already in its correct document (a test file's own test case is
  not a violation).

Flag only when the pattern sits inside a requirement statement or its
rationale and describes HOW the system works, not WHAT it does.

## Severity

- **HIGH** — implementation language inside a requirement statement itself.
- **MEDIUM** — useful information sitting in the wrong document (e.g.
  architecture rationale mixed into requirements).
- **LOW** — minor clarity issue or a missing cross-reference.

## Scope

Use for requirements-document audits, paired with
`writing-business-requirements`. Not for general document editing, code
review (`code-review` skill handles that), or authoring requirements from
scratch — author first, then audit.

## Related skills

`writing-business-requirements` — defines the standard this skill audits
against. Workflow: author with it, audit with this skill, review the
reported violations, apply the rewrites, relocate the extracted content.

## Limitations

The audit is human judgment, not a guarantee: a reviewer should confirm
findings before content is relocated. Pattern cues can miss
context-dependent violations and can't catch semantic problems that need
domain knowledge; a vague requirement with no implementation keywords is
found by reading, not by the catalog.
