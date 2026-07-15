---
name: writing-skills
description: Author or edit a skill for this framework — eval scaffolding written first, a description that routes correctly, a policy-free body per the house standard, admission only through a run record. Use when creating a new skill or pack, editing an existing skill's content or description, or reviewing a skill change before merge.
---

# Writing Skills

Job: produce a skill that triggers when it should, carries knowledge
rather than enforcement, works unchanged in any org, and enters the
framework only through its eval. The binding texts are in this skill's
references: `references/authoring-standard.md` (style and structure) and
`references/eval-discipline.md` (scenario/rubric/record formats).

## Rubric and scenario come first

Before drafting any skill text, write `evals/<name>/rubric.md` (3–6
observable behaviors, must-pass or advisory, plus a baseline expectation)
and `evals/<name>/scenario.md`. The scenario needs a trap a skill-less
model plausibly falls into — the rubric is where you discover what the
skill must actually change, and a scenario the baseline handles fine
proves nothing. The skill is not admitted until `record.md` exists: one
baseline run plus three with-skill runs, every must-pass present in all
three, verdict recorded. Authoring and evaluating are separate steps:
authoring ends with the skill, its rubric and scenario, and the plain
statement that the skill is unadmitted until its record exists. The eval
run itself is a separate piece of work the human commissions — don't
spin up eval runs as part of writing the skill (the framework repo's
`tools/eval-prep.sh` assembles the run protocol when that time comes).

## The description routes; the body teaches

`name` is lowercase-hyphenated and equals the directory. The description
is one sentence of what-it-is, then "Use when…" naming the concrete
requests that should fire it — triggers live only there, never in the
body. Check the name and trigger territory against client built-ins and
installed neighbors; where descriptions overlap, claim distinct territory
and defer to the neighbor explicitly in the description rather than
competing for the same prompt.

## Policy-free body

Portable discipline belongs in skill text; org-variable values — numbers,
tool names, formats, thresholds — flow through `policy:<key>`
consult-and-echo sentences with every key registered in `policy/KEYS.md`.
A value the registry doesn't cover means registering a new key
(expand-contract) or handing the value to the human for their policy
instance; either way the skill states a judgment default for when no
policy defines it. An inline policy value is a review-blocking defect.

## Style, briefly

The body opens with the job in its first three lines. Knowledge, not
compliance: no MANDATORY rhetoric, red-flag lists, or anti-rationalization
tables. Target 30–100 lines, ceiling 150; catalogs, templates, and
walkthroughs go to `references/` — moved, not deleted. Skills that touch
code carry the CONTEXT.md line; load-bearing sibling dependencies are
declared in `requires:`.

## Editing an installed skill

Any content edit invalidates the recorded eval (`install.sh --check`
flags the stale sha). Behavioral edits get re-run or a targeted
re-verification documented in the record; typo-class edits may be waived
with a one-line note; description-only edits re-verify triggering
instead — routing changed, behavior didn't.
