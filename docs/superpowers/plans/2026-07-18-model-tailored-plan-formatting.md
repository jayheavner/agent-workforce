# Model-Tailored Plan Formatting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax for tracking.

`execution-contract: 1`

**Goal:** The plan a builder receives is legible to the model that will execute it — Claude builders
get XML-structured dispatch framing, GPT/Codex builders get Markdown-header framing, reasoning-tier
upshifts get outcome-first framing — **without** the durable plan artifact ever becoming
model-specific, and without any of it shipping as an unmeasurable claim.

**Architecture.** Two things that "formatting" conflates are separated (design decision D1-D, confirmed
by the panel as the correct seam):

1. **The durable plan artifact** stays one canonical, model-neutral document authored once by the
   architect. It is upgraded so each load-bearing contract block is an explicitly delimited, named block
   (readable by both model families). This is model-*blind* by design.
2. **The dispatch envelope** the orchestrator wraps around the plan at dispatch time carries a small,
   model-appropriate framing. The orchestrator is the only actor that holds both the chosen model and the
   finished plan at the same moment, so framing lives there — dissolving the sequencing inversion (the
   architect never needs to know its reader).

Framing is modeled as **two composed axes, not one enum** (panel rec #2, Fowler): `notation(vendor)`
(XML for Claude, Markdown for GPT — a lossless re-encoding of identical fields) × `stance(tier)`
(outcome-first on a reasoning-tier upshift — which reorders emphasis). This prevents the "Claude,
reasoning-upshifted" cross-term from forcing a rewrite. **The envelope references plan blocks by their
named delimiters; it never restates their content** (panel rec #3, Fowler) — so framing can never
contradict the plan, and there is nothing to drift.

**Staging (panel rec #1 — Nygard/Fowler/Adzic).** The change ships in two stages because they carry
different reversibility and different evidence bars:

- **Stage 1 — structural, self-justifying, reversible-enough to ship on engineering merit.** The
  house-format upgrade, the two-axis envelope mechanism, the safe-fallback invariant, the drift test, and
  a telemetry field recording which framing was applied. Justified by changeability and safety alone — it
  is a strict improvement even at zero measured formatting benefit.
- **Stage 2 — the framing *content* claim, gated on measurement.** The assertion that a given framing
  improves builder output is NOT shipped as fact. Stage 1's telemetry field makes the effect observable;
  Stage 2 is only entered after a baseline shows a real signal. Stage 2 is scoped here but its tasks are
  gated behind the baseline read, not executed blind.

**Tech Stack:** Markdown (agent/skill prose), Python 3 (extends `scripts/render_codex_agents.py` and its
test `tests/test_codex_profiles.sh`), Bash + jq (consistent with existing hooks/tests). No new runtime
dependencies.

**Global Constraints (one line each, from project policy):**
- `policy:workspace-isolation` — source: this repo runs in git worktrees; value: all edits occur in the
  selected checkout `/Users/jay/claude/ai-agent-team/.claude/worktrees/fifty-one-dollar-fixes`. Implicit
  in every task.
- `policy:dependency-freshness` — N/A: no dependencies pinned or added.
- Files stay under the ~300-line ceiling; `agents/orchestrator.md` is already large — additions must be
  tight and must not push it toward the ceiling.
- Config-safety: validate every changed script (`python3 -m py_compile`, `bash -n`) before it counts as
  installed; the Codex profiles are **generated**, never hand-edited — regenerate via the render script.
- Security pass: no secrets in any prose, framing string, or telemetry record; framing carries no
  credential-shaped content; the telemetry field is a fixed enum, not free text.

**Single source of truth.** All framing rules live in exactly one file —
`skills/agent-workforce/references/plan-formatting.md`. Every other site (orchestrator, builder,
Codex-rendered profiles) **points at** it and does not restate the rules. A test enforces this (T5).

---

## Stage 1 — structural

## T1-house-format — Upgrade the plan house format to named delimited blocks

**Outcome:** Every new plan the planning skill produces renders its load-bearing contract blocks
(Interfaces/Invariants, Acceptance mapping, Executable examples, Escalation triggers) as explicitly
delimited, individually-named blocks rather than free prose — legible to both Claude (needs section
boundaries) and GPT (needs Markdown headers), with no model reference in the plan itself.

**Acceptance mapping:**
- [ ] AC-1 (mechanical): the planning skill defines a named-delimited-block convention for the four
  load-bearing block types. Check: `grep -nE "Interfaces and invariants|Acceptance mapping|Executable examples|Escalation triggers" skills/planning/SKILL.md` → expects all four present as named blocks; `grep -niE "model|sonnet|opus|gpt|claude|xml" skills/planning/SKILL.md || echo "why: house format must stay model-neutral — no model tokens expected"` → expects the fallback line to fire (no model tokens), proving neutrality.
- [ ] AC-2 (judgment): the block convention is genuinely parseable by both families, not just relabeled prose. Judge: reviewer. Bar: a "no" is a block that is still a prose paragraph with a heading — the named delimiter must bound the block so a reader can extract it unambiguously.

**Files and responsibilities:**
- Modify: `skills/planning/SKILL.md` — add the named-block convention to the existing "Tasks" section
  subsections; add one short subsection "Model-neutral by design" stating the plan carries no model
  reference and why (framing is the orchestrator's job at dispatch time). Point to
  `references/plan-formatting.md` for the framing rationale; do not restate framing rules here.

**Interfaces and invariants:**
- The four block names are a published two-sided interface (architect writes them, builder + envelope
  read them). Fix them exactly: `Interfaces and invariants`, `Acceptance mapping`, `Executable examples`,
  `Escalation triggers`. A rename is a breaking change (T2/T5 depend on these names).
- INVARIANT: the plan house format contains no model/vendor/tier token. This is the seam.

**Executable examples:**
- Given a plan authored under the new convention, When a reader extracts the `Interfaces and invariants`
  block by its delimiter, Then it gets exactly that block's content with no adjacent prose bleed.
- Boundary: a plan with an empty Escalation-triggers block still renders the named delimiter (empty is
  explicit, not omitted).

**Preflight checks:** confirm `skills/planning/SKILL.md` still has the section structure this task edits
(it did at plan time: "## Tasks" with the six `###` subsections); confirm the reviewer role is available
to judge AC-2.

**TDD and verification contract:** red — AC-1's grep for all four named blocks fails on the current file;
green — the grep passes and the neutrality grep fires its fallback. Broader: reviewer judges AC-2.

**Executor discretion:** exact wording of the convention prose and the "Model-neutral by design"
subsection; where within "## Tasks" the delimiter rule is stated. NOT discretionary: the four block
names, the no-model-token invariant.

**Escalation triggers:** if the current planning skill structure differs from preflight expectation such
that named blocks would collide with an existing contract → `PLAN_DEFECT`, stop.

**Commit intent:** `skills/planning/SKILL.md`. Subject: `feat(planning): name plan contract blocks for model-neutral parsing`.

---

## T2-framing-reference — Author the single-source framing reference

**Outcome:** One file defines the entire framing regime as two composed axes, and is the only place the
rules exist. Every other site cites it.

**Acceptance mapping:**
- [ ] AC-3 (mechanical): the reference defines both axes and all three framing outcomes. Check: `grep -niE "notation|stance|vendor|tier" skills/agent-workforce/references/plan-formatting.md || echo "why: two-axis model must be present"` → expects the two-axis vocabulary present; `grep -niE "un-framed|fallback|unrecognized" skills/agent-workforce/references/plan-formatting.md || echo "why: safe-fallback rule must be stated here as the single source"` → expects the fallback rule present.
- [ ] AC-4 (judgment): the reference is written so consumers can *point* at it rather than copy it — i.e., it names each framing outcome with a stable label the orchestrator/builder can cite. Judge: reviewer. Bar: a "no" is a reference whose rules can only be applied by paraphrasing them into the orchestrator.

**Files and responsibilities:**
- Create: `skills/agent-workforce/references/plan-formatting.md` — the axis definitions, the family→
  notation table (Claude→XML tags `<task>`/`<plan_reference>`/`<in_scope_slice>`/`<terminal_result>`;
  GPT→Markdown headers of the same fields), the tier→stance rule (reasoning-tier upshift → outcome-first,
  de-emphasize prescriptive step ordering), the **envelope-references-blocks-by-name-never-restates**
  rule, and the **safe-fallback invariant** (unrecognized/ambiguous vendor family → un-framed dispatch +
  a logged observable). Include one worked Given/When/Then example per notation (Claude XML envelope, GPT
  Markdown envelope) and one **malformed envelope that must be rejected** (panel rec #6, Adzic/Gregory).

**Interfaces and invariants:**
- Stable framing-outcome labels (e.g. `claude-xml`, `gpt-markdown`, `outcome-first`) — these are cited by
  the orchestrator prose and by the telemetry enum (T4). Fixed names.
- INVARIANT: this file is the sole definition; no framing rule is stated anywhere else (enforced by T5).

**Executable examples:** provided inline in the file itself (this task's deliverable *is* the examples the
panel required).

**Preflight checks:** confirm `skills/agent-workforce/references/` exists (it does — holds `roles.md`,
`model-policy.md`, `surface-compatibility.md`); confirm the vendor/tier vocabulary matches the
orchestrator's actual model tiers (Sonnet/Opus = Claude; Terra/Sol = GPT, per `model-policy.md`).

**TDD and verification contract:** red — the two grep checks fail (file absent); green — both pass.
Reviewer judges AC-4.

**Executor discretion:** the exact label strings (as long as T4's enum and T3's citations use the same
ones — pick once, use everywhere); the prose. NOT discretionary: presence of both axes, the fallback
rule, the by-name-never-restate rule, the three required examples including the malformed-reject one.

**Escalation triggers:** if the vendor/tier mapping in `model-policy.md` contradicts the two-axis model
(e.g., a model that is neither cleanly Claude nor GPT) → note it and apply the fallback rule as the
answer; do not invent a third notation without escalating as `PRODUCT_DECISION`.

**Commit intent:** `skills/agent-workforce/references/plan-formatting.md`. Subject: `feat(agent-workforce): add single-source plan-formatting framing reference`.

---

## T3-orchestrator-framing — Add the dispatch-framing rule to the orchestrator (cite, don't restate)

**Outcome:** The orchestrator, at the point it dispatches a builder (where it already names tier and
model), selects framing by composing notation(vendor) × stance(tier) **per the reference file**, applies
the safe fallback on an unrecognized family, and records which framing it applied.

**Acceptance mapping:**
- [ ] AC-5 (mechanical): the orchestrator's builder-dispatch section cites the reference and does not
  restate the rules. Check: `grep -nE "plan-formatting.md" agents/orchestrator.md || echo "why: orchestrator must cite the single source"` → expects the citation present; `grep -niE "<task>|<plan_reference>|xml for claude|markdown for gpt" agents/orchestrator.md || echo "why: orchestrator must NOT restate framing rules — cite only"` → expects the fallback line to fire (no restated rules).
- [ ] AC-6 (judgment): the added prose composes the two axes and states the fallback, without pushing
  `agents/orchestrator.md` toward the line ceiling. Judge: reviewer. Bar: a "no" is prose that duplicates
  the reference's tables, or that adds more than a tight paragraph to an already-large file.

**Files and responsibilities:**
- Modify: `agents/orchestrator.md` — in "## Execution contracts and builder results", add a tight
  paragraph: when dispatching a builder, wrap the plan reference in the framing selected by
  notation(vendor of chosen model) × stance(tier), per `references/plan-formatting.md`; on an
  unrecognized family, dispatch un-framed and note it; record the applied framing label for telemetry
  (feeds T4).

**Interfaces and invariants:**
- The framing labels used here MUST be the exact labels T2 defines.
- INVARIANT: the envelope references the plan's named blocks (T1) — it does not restate plan content.
- INVARIANT: framing is additive; an un-framed dispatch remains valid (backward compatibility).

**Executable examples:**
- Given a Sonnet builder chosen for a plan, When the orchestrator dispatches, Then the builder prompt
  wraps the plan reference in `claude-xml` framing and the telemetry `framing` field is `claude-xml`.
- Given an `EXECUTION_STALL` Opus retry on the same plan, When re-dispatched, Then the *same plan file* is
  referenced (no re-plan) under `claude-xml` + `outcome-first` stance; telemetry `framing` reflects the
  composed value.
- Failure/boundary: Given a model whose family the table doesn't recognize, When dispatched, Then the
  dispatch is un-framed and telemetry `framing` is `unframed-fallback`.

**Preflight checks:** confirm the "## Execution contracts and builder results" section exists (it does,
around the builder-envelope contract); confirm current line count of `agents/orchestrator.md` and that a
tight addition stays well under ceiling; confirm the telemetry field name chosen in T4.

**TDD and verification contract:** red — AC-5's citation grep fails; green — citation present and the
no-restate grep fires its fallback. Reviewer judges AC-6.

**Executor discretion:** placement and wording of the paragraph. NOT discretionary: citing rather than
restating; the fallback behavior; using T2's exact labels.

**Escalation triggers:** if adding the paragraph cannot be done without materially restating the
reference (because the orchestrator format demands inline rules) → `PLAN_DEFECT`, because the
cite-don't-restate invariant is load-bearing (it is what kills drift).

**Commit intent:** `agents/orchestrator.md`. Subject: `feat(orchestrator): frame builder dispatches per plan-formatting reference`.

---

## T4-telemetry-field — Record the applied framing so the effect is observable

**Outcome:** Every builder dispatch's telemetry record carries which framing was applied, making a future
A/B falsifiable (panel consensus + Nygard's "invisible by construction" concern — the wrong-framing path
now emits a signal).

**Acceptance mapping:**
- [ ] AC-7 (mechanical): the telemetry schema documents a `framing` field with a fixed enum. Check: `grep -nE "\"framing\"" docs/telemetry/README.md || echo "why: telemetry schema must document the framing field"` → expects the field documented; enum values match T2's labels plus `unframed-fallback`.
- [ ] AC-8 (mechanical): the scoreboard/query tooling can group first-try-pass by framing without
  erroring. Check: `bash tools/agent-team-scoreboard.sh <fixture.jsonl> 2>&1 | grep -iE "framing" || echo "why: scoreboard must surface the framing field, not error on it"` where `<fixture.jsonl>` is a telemetry line carrying a `framing` value → expects the field surfaced (fallback does not fire). If the tool needs a change to group by it, this task includes that change; validate the touched file with `python3 -m py_compile <file>` or `bash -n <file>` → expects exit 0.

**Files and responsibilities:**
- Modify: `docs/telemetry/README.md` — add `framing` to the v1 schema (or bump to v2 if the schema is
  versioned and adding a field requires it — preflight decides), enum = T2's labels + `unframed-fallback`
  + `n/a` for non-builder roles.
- Modify (candidate): `tools/agent-team-scoreboard.sh` and/or the telemetry-writing path invoked on the
  scribe's closeout dispatch — only as needed so the field is written and queryable. Mark `candidate`;
  preflight confirms which file writes the record.
- Modify (candidate): the closeout/telemetry instruction in `agents/orchestrator.md` so the scribe is
  given the applied framing label to record (joins T3's recorded label to the telemetry write).

**Interfaces and invariants:**
- `framing` enum values are exactly T2's labels; a value outside the enum is invalid.
- INVARIANT: telemetry stays best-effort and never a gate (existing rule) — a missing `framing` field
  degrades to `n/a`/unknown, never blocks closeout.

**Executable examples:**
- Given a builder dispatch framed `claude-xml`, When the closeout telemetry is written, Then its record's
  `framing` is `claude-xml`.
- Boundary: Given a scribe/verifier (non-builder) dispatch, Then `framing` is `n/a`.

**Preflight checks:** read `docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md` and the
telemetry README fully; confirm whether the schema is versioned and whether adding a field is a v-bump;
confirm the exact file that writes telemetry records and the query tool's grouping mechanism.

**TDD and verification contract:** red — grep for `"framing"` in the README fails; green — field
documented and the query tool handles a fixture line. Follow the telemetry spec's own conventions for
schema evolution.

**Executor discretion:** whether this is a v1 field-add or a v2 bump (per what the spec requires);
internal tooling structure. NOT discretionary: the enum matching T2; best-effort/never-a-gate invariant.

**Escalation triggers:** if the telemetry spec forbids adding fields without a formal schema-version
process that exceeds this plan's scope → `PLAN_DEFECT`, surface to orchestrator for a spec amendment
rather than bypassing the schema discipline.

**Commit intent:** `docs/telemetry/README.md` plus the minimal tooling/orchestrator edits. Subject:
`feat(telemetry): record applied dispatch framing for A/B observability`.

---

## T5-drift-test — Enforce single-source framing across all surfaces

**Outcome:** A test fails at build/CI time if the framing rules drift between the reference file, the
orchestrator's citation, the builder's citation, and the regenerated Codex profiles — converting the
panel's #1 drift risk from a hope into an enforced invariant.

**Acceptance mapping:**
- [ ] AC-9 (mechanical): a test asserts the reference is the sole definition and that consumers cite it.
  Check: `bash tests/test_plan_formatting_drift.sh; echo "exit=$?"` → expects `exit=0` on the current
  tree. Red demonstration (same command): temporarily copy a framing rule verbatim into
  `agents/orchestrator.md`, run `bash tests/test_plan_formatting_drift.sh; echo "exit=$?"` → expects a
  non-zero exit naming the duplication, then revert the injection.
- [ ] AC-10 (mechanical): regenerating Codex profiles produces no diff. Check: `python3 scripts/render_codex_agents.py` then `git diff --exit-code codex/ || echo "why: rendered profiles must match checked-in; regenerate, do not hand-edit"` → expects clean (no diff).

**Files and responsibilities:**
- Create: `tests/test_plan_formatting_drift.sh` (or extend `tests/test_codex_profiles.sh` if that is the
  established home — preflight decides) — asserts: (a) the framing-rule vocabulary appears only in
  `plan-formatting.md`, not restated in orchestrator/builder; (b) orchestrator and builder each contain
  the citation to the reference; (c) the builder role body (which the Codex render copies verbatim) still
  cites the reference after render.
- Modify (candidate): `scripts/render_codex_agents.py` only if the builder's framing-citation line needs
  to survive rendering intact and currently would not.

**Interfaces and invariants:**
- The test is the enforcement mechanism for T2's single-source invariant and T3's cite-don't-restate
  invariant. It is the teeth the panel demanded behind "single source of truth."

**Executable examples:**
- Given the current tree, When the drift test runs, Then it exits 0.
- Given a framing rule copied verbatim into `agents/orchestrator.md`, When the drift test runs, Then it
  exits non-zero naming the duplication.

**Preflight checks:** read `tests/test_codex_profiles.sh` to match the house test style; confirm how
existing tests are run (there is a `tests/` dir with shell tests); confirm `render_codex_agents.py`'s
`role_body` copies the builder body verbatim (it does — splits frontmatter, takes part 3).

**TDD and verification contract:** red — the drift test does not exist / fails to catch an injected
duplication; green — it passes clean and catches the injection. AC-10's render check must be clean.

**Executor discretion:** test implementation language/structure within the existing test conventions;
whether to extend the codex test or add a new one. NOT discretionary: that drift is actually caught
(demonstrate the red), and that render produces no diff.

**Escalation triggers:** if the builder's citation cannot survive Codex rendering without changing
`render_codex_agents.py` in a way that touches other roles → return findings; a render-script change with
broad blast radius is a `PLAN_DEFECT` needing an amendment, not silent scope creep.

**Commit intent:** `tests/test_plan_formatting_drift.sh` (+ candidate render tweak). Subject:
`test(agent-workforce): enforce single-source plan-formatting across surfaces`.

---

## T6-builder-line — Tell the builder framing primes, plan governs

**Outcome:** The builder treats the dispatch framing as priming only; the plan file (and its named
blocks) remains the authoritative contract, so a mis-framed or reasoning-restanced dispatch can never
override a load-bearing plan constraint.

**Acceptance mapping:**
- [ ] AC-11 (mechanical): the builder definition states framing-primes/plan-governs and cites the
  reference. Check: `grep -niE "framing|plan-formatting.md" agents/builder.md || echo "why: builder must acknowledge framing and cite the reference"` → expects both present; `git diff --exit-code codex/agents/agent_workforce_builder.toml` after `python3 scripts/render_codex_agents.py` → expects the builder Codex profile regenerated to include the line (no manual diff).
- [ ] AC-12 (judgment): the line closes Fowler's framing-vs-plan-conflict without weakening the plan's
  authority. Judge: reviewer. Bar: a "no" is wording that lets outcome-first stance excuse skipping an
  ordered plan step — the plan's Interfaces/Invariants and step ordering always govern.

**Files and responsibilities:**
- Modify: `agents/builder.md` — one tight sentence in "Contract consumption": the dispatch may arrive in
  model-appropriate framing that primes reading order/emphasis; the plan file and its named blocks remain
  authoritative; on any conflict, the plan governs. Cite `references/plan-formatting.md`; do not restate
  framing rules (T5 enforces).
- Regenerate: `codex/agents/agent_workforce_builder*.toml` via the render script (verbatim body copy).

**Interfaces and invariants:**
- INVARIANT: plan governs over framing on any conflict. This is the safety backstop that makes the
  misclassification blast radius = "degraded to un-framed," not "corrupted."

**Executable examples:**
- Given a plan with strictly ordered steps and an outcome-first-framed dispatch, When the builder
  executes, Then it still honors the plan's step ordering (framing did not license reordering).
- Given a Claude builder that received GPT-Markdown framing by misclassification, When it executes, Then
  output correctness is unchanged because the plan governed (this is the T3 fallback's safety claim made
  real at the builder).

**Preflight checks:** confirm "## Contract consumption" exists in `agents/builder.md` (it does, first
body section); confirm the render script copies the builder body verbatim so the line propagates.

**TDD and verification contract:** red — grep for the framing acknowledgment fails; green — present and
Codex profile regenerated clean. Reviewer judges AC-12.

**Executor discretion:** exact sentence wording; placement within Contract consumption. NOT
discretionary: plan-governs-on-conflict; citing not restating.

**Escalation triggers:** none expected; if the render produces a diff in a non-builder profile, stop —
that is unexpected blast radius (`PLAN_DEFECT`).

**Commit intent:** `agents/builder.md` + regenerated `codex/agents/agent_workforce_builder*.toml`.
Subject: `feat(builder): framing primes, plan governs on conflict`.

---

## Stage 2 — the framing-content claim, GATED on measurement (do not execute blind)

> **Gate:** Stage 2 tasks are entered ONLY after Stage 1 has run in production long enough to produce a
> baseline, and the baseline shows a real signal. The orchestrator (not the builder) reads the baseline
> and decides. Executing Stage 2 without the baseline read is the exact "ship an unmeasured claim" the
> panel rejected.

## T7-baseline (gate task) — Establish the pre-change baseline and sensitivity check

**Outcome:** A documented baseline of builder first-try-pass rate by model family from existing
telemetry, AND an explicit finding on whether the telemetry `verdict` bit is sensitive enough to detect a
formatting effect at all (Gregory/Crispin's open question — the verdict is a coarse accept/reject bit).

**Acceptance mapping:**
- [ ] AC-13 (mechanical): baseline computed from real telemetry. Check: `bash tools/agent-team-scoreboard.sh 2>&1 | grep -iE "resolved_model|first.?try|pass" || echo "why: scoreboard must emit first-try-pass by model, or the baseline doc must record insufficient-data with the record count"` → expects the grouped baseline figures to appear, or the baseline doc to state `insufficient data — N records` with a real N.
- [ ] AC-14 (judgment): a stated verdict on measurement sensitivity. Judge: human. Bar: a "no" is
  proceeding to T8 when the baseline has too few records or the verdict bit provably can't separate
  "framing helped" from "task was easy."

**Files and responsibilities:**
- Create: `docs/telemetry/plan-formatting-baseline-<date>.md` — the baseline numbers and the sensitivity
  finding.

**This is a research/measurement task, not a code change.** It is `domain-uncertified` against the
question "does framing measurably help" until the data exists.

**Escalation triggers:** insufficient telemetry volume, or a finding that the verdict bit can't detect
the effect → `PRODUCT_DECISION` to the human: enrich telemetry with a finer quality signal (new scope),
or ship framing on published-guidance basis with the effect declared unmeasured, or stop. Do NOT silently
proceed.

**Commit intent:** `docs/telemetry/plan-formatting-baseline-<date>.md`. Subject: `docs(telemetry): baseline builder pass rate by model family before framing rollout`.

## T8-content-tuning (gated) — Tune framing content against the measured effect

**Gated behind T7's human decision.** Scoped, not detailed, because its content depends entirely on what
T7 finds. If T7 shows a signal: A/B the framing labels (using T4's `framing` field as the split variable)
and tune the reference's framing content toward the measured winner. If T7 shows no usable signal: this
task becomes "document that framing ships on published-guidance basis, effect unmeasured" — an honest
label, not a claimed improvement. The architect writes the T8 detail as an amendment once T7 returns.

---

## Self-review (planning-skill discipline)

1. **Coverage:** every panel prioritized recommendation maps to a task — split-into-stages (Stage 1/2
   structure), two-axis model (T2/T3), envelope-references-by-name (T2 invariant, T3 invariant), close Q5
   as invariant (T2 fallback + T3 + T6), drift lint/test (T5), falsifiable criteria + baseline + examples
   (T4, T7, T2's required examples), house-format vs envelope split shipped separately (Stage 1 T1 then
   T3). Nygard's "ship format before envelope" is honored by task ordering within Stage 1 (T1 precedes
   T3) and the two-stage split.
2. **Placeholder scan:** no TBD/TODO. `candidate` paths (T4 telemetry writer, T5 test home, T5 render
   tweak) are explicitly labeled for preflight, not guessed. T8 is deliberately scoped-not-detailed
   because it is gated on T7's data — this is a stated gate, not a placeholder.
3. **Consistency:** framing labels defined once in T2 and referenced by T3/T4/T6; the four block names
   fixed in T1 and consumed by T2/T3/T5.
4. **Architect intent:** the seam (plan model-neutral, framing at dispatch) survives every task; the
   two-axis decomposition and cite-don't-restate rules (the panel's structural upgrades) are invariants,
   not prose.
5. **Builder feasibility:** all paths verified to exist at plan time except the labeled `candidate`s;
   commands are real (`render_codex_agents.py`, `test_codex_profiles.sh`, the scoreboard tool all exist);
   the render script's verbatim-body-copy behavior was confirmed so the builder-line propagation is real.
6. **Verifier observability:** every AC is either a named command with expected output (with `|| echo`
   reasons so failures print why) or an explicitly-labeled judgment criterion with a named judge and a
   real "no" — none are tautologies, none are bare exit-0.

DRY. YAGNI. TDD. Frequent commits.

## Decision inventory (this plan's own consequential calls)

- **Two-stage split** — consequential (changes what ships when). Options: ship all at once (rejected —
  bundles reversible envelope with semi-irreversible format change and ships an unmeasured claim) vs.
  two stages (chosen). Reasoning: Nygard's reversibility argument + the measurement consensus both point
  the same way. Resolved.
- **Cite-don't-restate as an enforced invariant, not a convention** — consequential (it's the whole
  anti-drift mechanism). Chosen over a prose "single source of truth" note because five experts said a
  doc others copy is a doc that drifts. Resolved via T5's test.
- **Two composed axes vs one family enum** — consequential (Fowler: the cross-term forces a rewrite
  otherwise). Chosen: two axes. Resolved.
- **Telemetry field in Stage 1, not Stage 2** — consequential. Reasoning: you cannot A/B a treatment you
  don't log; the observable must exist before the claim is testable. Resolved.
- Naming of the drift test file, the `framing` enum strings, block-delimiter syntax — not consequential:
  any consistent choice works as long as T2's labels are reused everywhere.

## Genuine either/or for the human (at the Stage-2 gate, not now)

Only one, and it is deferred to T7's finding, not asked upfront: **if the existing telemetry verdict bit
proves too coarse to measure the framing effect, do we (a) enrich telemetry with a finer quality signal,
(b) ship framing on published-guidance basis with the effect declared unmeasured, or (c) stop at Stage 1
structure and not tune content at all?** This is a real value judgment (cost of measurement vs. value of
a tuned-vs-untuned framing) and belongs to the human — but only once T7 shows whether it even arises.
