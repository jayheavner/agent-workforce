# Design: model-tailored plan formatting for builder dispatches

**Date:** 2026-07-18
**Status:** design, pre-panel
**Author:** architect-mode session (investigating the "does the planner format plans for the executing builder model" question)

---

## 1. Problem statement

The agent team's planner (the **architect**) writes an implementation plan; a separate **builder**
agent reads that plan and writes code. Prompt-formatting research is unambiguous that model families
parse structure differently: Claude models parse XML tags natively (Anthropic's own docs make XML the
primary structuring recommendation), GPT-family models favor Markdown headers, and reasoning-tier
models respond better to outcome statements than to prescriptive step lists. The effect is largest for
**analytical** work and largest **across vendors**; the within-vendor tier delta (Sonnet vs Opus) is
real but smaller.

Today the plan is written in **one fixed house format for every builder**, model-blind. Confirmed by
inspection of `skills/planning/SKILL.md`, `agents/architect.md`, and `agents/builder.md`: there is no
reference anywhere to the executing model, no conditional formatting, no XML-vs-Markdown choice.

### 1.1 The structural obstacle (the crux)

The plan format cannot simply be "tailored by the architect" because of a **sequencing inversion**:

1. The **architect** writes the plan first and is never told which model the builder will run on.
2. The **orchestrator** picks the builder model *afterward* — Sonnet by default, Opus when
   `agents/orchestrator.md`'s "initial Opus dispatch is required when any one is true" triggers fire —
   by reading the finished plan.

So at authoring time the writer does not know its reader. Any fix must resolve this ordering, not just
add formatting rules.

### 1.2 Cross-surface scope

"The builder model" is not only Sonnet-vs-Opus. The team ships a Codex/ChatGPT variant
(`codex/`, `skills/agent-workforce/references/model-policy.md`) where builders run on GPT-family models
(Terra/Sol). Cross-vendor is exactly where the formatting delta is largest — so a fix that ignores the
Codex surface addresses the *smaller* half of the effect and skips the larger half.

---

## 2. Decision inventory

### 2.1 Consequential decisions

**D1 — Where does model-awareness enter, given the sequencing inversion?**

Options considered:

- **A. Architect writes model-specific plans.** Rejected. Requires the orchestrator to pick the builder
  model *before* the plan exists, inverting the current (correct) flow where model choice is informed by
  the finished plan's complexity. Also forces a re-plan whenever the model changes (e.g., an
  `EXECUTION_STALL` Opus retry), which is exactly when re-planning is most disruptive.

- **B. A separate "reformat" pass converts the plan per target model.** Rejected. Adds an agent hop and
  a second artifact to keep in sync; a lossy translation layer between plan and builder is a new failure
  surface (drift between the "canonical" plan and the "reformatted" plan). Violates the team's
  minimal-artifacts discipline.

- **C. The plan is authored in one model-neutral house format; the *consuming* builder adapts its own
  reading.** The builder already knows its own model at runtime. But a builder cannot restructure a plan
  it is handed — it can only read it. So this alone does nothing for formatting.

- **D. (dissolving the binary) Separate the two things that "format" conflates: (i) the *durable plan
  artifact* stays one model-neutral, well-structured house format, authored once; (ii) the *dispatch
  envelope* the orchestrator wraps around the plan carries a small, model-appropriate framing that
  primes the specific builder.** The orchestrator already picks the model and already writes the dispatch
  prompt (`agents/orchestrator.md` §"Execution contracts and builder results"). It is the one actor that
  knows both the model and the plan at the same moment. So the tailoring lives in the *dispatch framing*,
  authored by the orchestrator at the exact point where model and plan are both known — not in the plan
  file, and not in a new agent.

**Chosen: D.** It dissolves the sequencing inversion instead of fighting it. The plan artifact stays
canonical, model-neutral, and re-usable across a model change (an Opus retry re-reads the *same* plan
with different framing — no re-plan). The house format itself is upgraded to be *natively legible to
every target* (see D2). The per-model priming is a light, cheap framing string, not a translation.

**D2 — What is the model-neutral house format, concretely?**

The current plan format is Markdown with prose sections. Research says Claude prefers explicit XML-tag
section boundaries; GPT prefers Markdown headers; both *can* read the other. A format that is maximally
legible to both is **Markdown headers as the outer skeleton with explicit, named section delimiters**
that read as unambiguous boundaries to either parser — i.e., keep the Markdown `##` headers (GPT-native)
but make each load-bearing contract block (Interfaces/Invariants, Acceptance, Executable Examples,
Escalation triggers) a clearly delimited, individually-labeled block rather than free prose. This is the
intersection, not a compromise: both families read labeled, bounded blocks well. We do **not** convert
the whole plan to XML (hurts GPT and human readability) nor leave it as loose prose (hurts Claude's
section parsing).

Open question for the panel: is the intersection format actually as good for Claude as native XML would
be, or are we leaving Claude performance on the table to serve cross-vendor legibility? (See §5.)

**D3 — What does the per-model dispatch framing contain?**

A short, declared framing block the orchestrator prepends to the builder dispatch, selected by target
model family:

- **Claude builder (Sonnet/Opus):** wrap the standing builder instructions and the in-scope acceptance
  slice in XML-tagged sections (`<task>`, `<plan_reference>`, `<in_scope_slice>`, `<terminal_result>`),
  since the dispatch prompt itself (not the plan file) is where Claude's XML-parsing advantage pays off.
- **GPT builder (Terra/Sol):** Markdown-header framing of the same fields.
- **Reasoning-tier upshift (Opus / Sol at max):** lead with the *outcome and invariants*, de-emphasize
  prescriptive step ordering (which reasoning models tend to over-follow or resent), consistent with the
  "reasoning models want outcomes" finding.

This is framing of the **dispatch**, which the orchestrator already authors — not a rewrite of the plan.

**D4 — Is the within-Claude Sonnet-vs-Opus delta worth tailoring at all?**

The research says the within-vendor tier delta is the *smallest* of the three effects. Tailoring
Sonnet-vs-Opus framing risks over-engineering for a small gain. Tentative position: tailor by **vendor
family** (Claude vs GPT) as the primary axis — the large effect — and apply the **reasoning-outcome**
framing on the upshift path (the second-largest effect), but do **not** maintain distinct Sonnet-vs-Opus
formatting beyond that. This keeps the change proportional. (Panel question in §5.)

### 2.2 Trivial decisions

- File location for the guidance: extend `skills/agent-workforce/references/` with a formatting
  reference rather than a new top-level doc — `not consequential:` it's where surface/model policy
  already lives.
- Naming of the framing block: `dispatch framing` — `not consequential:` any clear label works.
- Whether to touch the Codex `.toml` profiles: they carry role prose, so the same guidance flows through
  the installer's profile generation — `not consequential:` mechanical, follows existing generation path.

---

## 3. Proposed change surface

1. **`skills/planning/SKILL.md`** — upgrade the house format: make each load-bearing contract block an
   explicitly delimited, labeled block (D2). One added subsection stating the format is model-neutral by
   design and why. No per-model content in the plan itself.

2. **`agents/orchestrator.md`** — in the "Execution contracts and builder results" section, add the
   dispatch-framing rule (D3): the orchestrator selects framing by the builder model family it just
   chose. This is the actor that knows both plan and model.

3. **`skills/agent-workforce/references/` — new `plan-formatting.md`** — the reference table: model
   family → framing style, with the Claude-XML / GPT-Markdown / reasoning-outcome rows and the rationale.
   Cited by both the orchestrator and the planning skill.

4. **`agents/builder.md`** — one line acknowledging the dispatch may arrive in model-appropriate framing
   and that the *plan file* remains the authoritative contract (framing primes, plan governs) — so a
   builder never treats framing as overriding the plan.

5. **Codex parity** — the same orchestrator/planning prose regenerates into the `.toml` profiles via the
   existing installer path; verify no divergence.

---

## 4. Why this is proportional and safe

- No new agent, no new artifact, no re-plan on model change.
- The plan stays canonical and model-neutral; framing is additive and lives where model+plan are both
  known.
- Backward-compatible: an un-framed dispatch still works (the plan governs); framing is an enhancement,
  not a gate.
- Cross-vendor coverage included, because that is where the measured effect is largest.

---

## 5. Open questions for the expert panel

1. **D2 intersection vs native XML:** Does the model-neutral "labeled bounded blocks in Markdown" format
   leave meaningful Claude performance on the table versus native XML in the plan file itself? Is the
   dispatch-envelope XML framing (D3) sufficient to recover Claude's parsing advantage, or does the
   *plan body* also need to be XML for Claude builders?

2. **D4 tier granularity:** Is tailoring by vendor family (Claude/GPT) + reasoning-outcome-on-upshift the
   right granularity, or is the Sonnet-vs-Opus distinction worth its complexity?

3. **Evidence bar:** This design rests on published prompt-formatting guidance, not on this team's own
   measured builder outcomes. Should the change ship on the published-guidance basis, or should it be
   gated behind an A/B measurement using the team's existing telemetry (`docs/telemetry/`)?

4. **Maintenance drift:** The framing lives in three places (planning skill, orchestrator, reference doc)
   plus Codex profiles. Is a single-source-of-truth reference with the others *pointing* to it enough to
   prevent drift, or does this need a lint/test like `tools/lint_acceptance_checks.py`?

5. **Failure mode:** If the orchestrator mis-identifies the model family and applies GPT framing to a
   Claude builder (or vice versa), what is the blast radius, and is it worth a guard?
