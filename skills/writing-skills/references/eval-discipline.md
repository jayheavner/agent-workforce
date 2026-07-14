# Eval Discipline

A skill enters `core/` or a pack only with one documented behavioral eval
whose pass criterion is explicit. Model behavior is stochastic; one lucky
run is an anecdote, not a gate.

## The three files

`evals/<skill>/` holds:

- **`scenario.md`** — the setup: a task prompt plus any fixture files. It
  must contain a **trap** the discipline exists to catch. A scenario a
  skill-less model handles fine proves nothing — when a baseline turns
  out to pass anyway (strong models increasingly do), record that as a
  documented discriminator weakness rather than pretending otherwise,
  and name what the skill's *observable delta* actually is.
- **`rubric.md`** — 3–6 observable behaviors, each marked **must-pass**
  or **advisory**, plus a **baseline expectation** naming which behaviors
  a skill-less run is expected to miss. Write the rubric before the skill
  text: the rubric is where the author discovers what the skill must
  actually change.
- **`record.md`** — dated evidence with frontmatter:

  ```
  ---
  skill-sha256: <sha256 of SKILL.md at evaluation time>
  date: YYYY-MM-DD
  commit: <short sha>
  ---
  ```

  followed by one **baseline (no-skill) run** — unconditionally; the
  baseline is what makes "the trap discriminates" falsifiable — and
  **three with-skill runs**, with a per-must-pass present/absent judgment
  per run, and a verdict: **admitted** or **NEEDS CONTENT FIX**. Every
  must-pass must be present in all three runs; a miss is a documented
  judgment call, not a silent pass.

## Running

Runs are manual or agent-driven — sandboxed working copies, the baseline
barred from reading any skill, the with-skill runs pointed at the skill
files (plus its `requires:` dependencies) and told to follow them exactly.
Have each run return a faithful ordered trace (commands verbatim with
output, files changed, actions executed vs proposed) so must-pass
judgments rest on evidence, and prefer objective checks — transcript
greps, fixture logs, git state — over the run's self-report where the
rubric allows it.

## Policy-consuming skills

Additionally exercise the precedence contract: a fixture with conflicting
project-scope and user-scope values for one consulted key, where a rubric
behavior is observable only under correct per-key resolution and the echo
names the winning source. Where only one scope exists in the run
environment, record which path was demonstrated (e.g. user-scope fallback)
and point at where full precedence is covered.

## Staleness

`record.md`'s sha makes staleness computable; `install.sh --check` warns
when a skill's content changed after its recorded eval. Behavioral edits
require a re-run (a targeted re-verification of the changed behavior is
acceptable, documented in the record). Typo-class edits may be waived
with a one-line note. Description-only edits change routing, not
behavior — re-verify *triggering* (see `evals/triggering/`) and note the
waiver with the updated sha.
