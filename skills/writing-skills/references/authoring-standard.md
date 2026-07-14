# House Skill Authoring Standard

Every skill in `skills/` follows this standard. Preloaded skills carry knowledge,
not enforcement: hooks enforce "can't", the roster and dispatch decide "when" —
a skill teaches only "how" and "what good looks like".

## Knowledge, not compliance

- No trigger-phrase sections, no MANDATORY / Iron-Law rhetoric, no
  anti-rationalization tables. Write for a competent reader already committed to
  doing the work well.
- No enforcement theater: if a rule needs enforcing, it belongs in a hook, not in
  bold capitals.
- The line is theater vs. knowledge, not tone. A catalog of domain **failure
  modes** — tdd's tautological/implementation-coupled anti-patterns,
  ux-to-ui-design's design anti-patterns and its tells that you skipped the UX
  phase — is knowledge a competent reader still wants named, and is fine. What's
  banned is rhetoric aimed at the reader's *compliance*: "you're rationalizing"
  tables, a "Thought / Reality" column that argues them out of skipping the
  skill, capitalized threats. Name failure modes as content; don't browbeat.

## Job in the first three lines

A reader — human or model — knows what the skill is for without scrolling: the
body opens with one to three lines stating the job and when the skill applies.

## Policy-free rule

Framework skills contain no policy values — no numbers, formats, or tool
mandates. Where behavior depends on policy, use the consult-and-echo sentence:

> Resolve `policy:<key>` from the project policy and state the resolved value
> and its source — project policy / user policy / judgment default — before
> applying it. Where no policy defines it: <judgment default>.

Keys come only from `policy/KEYS.md`; only tokens of the form `policy:<key>`
listed there may appear. A policy value or unregistered key token in a
framework skill is a review-blocking defect. Resolution semantics (per-key,
project overrides only keys it names) are defined once in
`policy/PROJECT-POLICY-TEMPLATE.md` — point at them, never restate them.

## Frontmatter

`name` (= directory), `description` (one sentence what-it-is, then "Use when…"
with concrete triggers — triggers live here, never in the body), optional
`requires: [<sibling>]` for load-bearing cross-skill dependencies, optional
`disable-model-invocation: true` for user-invoked-only skills.

## Moved, not deleted

Over-budget content moves to a sidecar the SKILL.md links. "Moved" is
operational: a diff removing content with no sidecar destination is a
review-blocking defect.

## CONTEXT.md habit

Skills touching code carry one line: read `CONTEXT.md` if present so names match
the project's domain language; respect ADRs in the area touched. Convention:
`docs/context-convention.md`.

## Name precedence

Framework names avoid client built-ins (`reviewing` not `code-review`,
`verifying` not `verify`). If a future client built-in collides, the documented
escape is the mechanical `fw-<name>` prefix rename.

## Long material goes to references/

Pattern catalogs, walkthroughs, worked examples, tool lists, and templates live
in `references/` inside the skill's directory and are read on demand. Preload
weight is for judgment, not lookup tables.

## Size

- Target 30–100 lines for most skills.
- Hard ceiling 150 lines, except `reviewing`, `convene-panel`, and
  `ux-to-ui-design` (200). Ceilings are stated in this document and checked by
  review, not enforced by an installer.
- Over budget? Move content to `references/`.

## Questionable policy gets flagged, not silently preserved or dropped

If a rule looks wrong, obsolete, or contradictory while editing a skill, keep it
verbatim and flag it in the active implementation plan's decision queue with a
recommendation. Rulings are made by a human at plan review, not mid-edit.
