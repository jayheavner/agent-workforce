---
name: convene-panel
description: Convene a panel of named experts against an artifact — discussion, debate, or socratic mode — with required per-expert dissent and a five-section synthesis that never averages disagreement. Use when the user asks for a panel, an expert review of a spec/plan/document, or a structured multi-perspective critique.
---

# Convene Panel

Job: structured multi-expert critique of an artifact — a spec, plan, document,
or decision — using a roster file. This skill owns the mechanics; experts are
data. Shipped rosters: `rosters/spec.md`, `rosters/business.md`.

## Convening

1. Read the artifact in full, the framed question the convener wants
   answered, then the roster file.
2. Validate the roster: 3–10 experts, each section carrying a name, framework,
   methodology, and critique focus. Outside 3–10, stop and say what's wrong
   rather than convening a malformed panel.
3. Select experts: the full roster by default. Convene a subset only when the
   artifact clearly doesn't touch an expert's domain — and name who was left
   out and why, so the exclusion is reviewable.
4. Pick a mode (below); default is discussion unless the convener asks otherwise.
5. Produce per-expert output, then the synthesis. Every expert speaks through
   their own framework and vocabulary — an expert whose output could have come
   from any other expert has not been convened, only name-dropped. Success is
   contested points traceable into the convener's decision queue; a panel that
   returns nothing decision-relevant should say so rather than pad.

## Modes

- **Discussion** — experts speak in sequence, each building on, refining, or
  concretely extending what earlier experts said. Best for improving an artifact.
- **Debate** — each expert attacks the strongest claims made so far, their own
  side included; disagreements are sharpened rather than smoothed. Best for
  stress-testing a decision before commitment.
- **Socratic** — experts only ask questions, from their framework, no answers or
  prescriptions. Best for exposing unexamined assumptions early in design.

## Required dissent

In every mode, every expert ends their turn with their single strongest
objection to the artifact — even when broadly positive. Format:

**Strongest objection:** <one to three sentences, in the expert's voice>

This is the structural counter to roleplay convergence; an expert with no
objection is repeating the room. A dissent that restates another expert's
point is vacuous and fails; see references/dissent-examples.md for a judged
pair.

## Synthesis

After all experts, the convener writes exactly five sections:

1. **Consensus points** — what multiple experts independently support.
2. **Contested points** — each with who disagrees and why, stated as the
   disagreement it is. Contested points are never averaged into false consensus;
   a real disagreement is a finding, not a formatting problem.
3. **Blind spots** — what no expert's framework captured adequately.
4. **Open questions** — what no expert could resolve from the artifact alone.
5. **Prioritized recommendations** — ordered, actionable, each traceable to the
   expert reasoning above.

## Invocation modes

- **Standalone** (default, any session): single-context roleplay — one model
  voices all experts. Cheap; convergence risk is real, which is what required
  dissent exists to counter.
- **Dispatched** (any session with subagent/collaboration tools): one subagent per expert.
  Each receives only the artifact and its own roster entry — no expert sees
  another's output — using `references/dispatch-template.md`; the convener
  synthesizes the independent returns. Before dispatching, state the estimated
  cost (experts × one subagent turn each) and get a go-ahead. High-stakes mode;
  the orchestrator may use it at gates when the human asks. The expert reply's
  canonical form is a findings block plus the mandatory dissent line. An
  expert that returns nothing, or returns without the dissent line, is named
  in the synthesis under a **Non-responses** heading — never silently
  synthesize around a missing expert.

## Extending

A new panel is a new roster file in `rosters/` following the same per-expert
format. No engine changes.
