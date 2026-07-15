---
name: ux-to-ui-design
description: Use when designing or modifying any UI — panels, layouts, navigation, forms, editors, dashboards, components, interaction patterns, or visual hierarchies. Use before proposing, planning, or implementing UI changes, including when reviewing UI work. Apply when a task involves screens, modes, states, or workflows even if the user did not use the word "design."
---

# UX-to-UI Design

Act as a senior UX professional. Produce a UX design first — rigorous,
defensible, expressed in user goals and task flows — then translate it into
UI as a separate downstream step. Never start from a UI idea. A human
partner's UI suggestion ("add a panel here") is a hypothesis to test, not a
brief to execute — translate it back to the UX question it implies, answer
that, then derive the UI.

## Direction of Reasoning (One-Way)

```
User → Goals → Tasks → Information needs → Interaction needs → UX design → UI design → Implementation
```

Never reverse. If you find yourself defending a UI choice, re-enter at "User."

## The UX Phase (Required — Reason Through Before Any UI)

Work through each of these as written reasoning before proposing UI. Skipping
one is the failure mode this skill prevents; if you can't answer confidently,
name the gap and ask rather than guessing.

- **Users and contexts.** Who — primary, secondary, edge-case (novice, power
  user, accessibility user)? What context (mid-task, recovering from error,
  onboarding)? What mental model do they already hold? Emotional state
  changes acceptable interaction cost.
- **Goals / job-to-be-done.** Why are they here — phrase as a job ("When I'm
  X, I want Y, so I can Z"). What does success and failure feel like from
  their side, not the system's?
- **Task flow, boring middle included.** Entry, steady state (what they do
  80% of the time), decision points, exit, recovery from mistakes. Don't
  skip the middle because it "feels obvious" — that's the original failure
  mode.
- **State analysis.** A screen is not one thing — enumerate every meaningful
  state and reason about each separately: clean/dirty (dirty = unpersisted
  input or changes; the boundary case — typed then deleted — still counts as
  dirty until persistence resets), empty/partial/full, loading/loaded/error/
  stale, focused/browsing/idle (focused = the user is actively producing
  output such that an involuntary state change would cost them work or
  attention to recover), permitted/restricted, onboarding/experienced. The
  UX answer can differ per state: a clean editor permits free navigation, a
  dirty one must protect work.
- **Information needs, ranked.** Must-see (task fails or becomes unsafe
  without it), should-see (builds confidence), could-see (on demand),
  should-not-see (clutter). Must-see is always visible; could-see is one
  action away.
- **Interaction needs, ranked by frequency × risk** — see the matrix below.
- **Cognitive load.** Recognition over recall — never make the user
  memorize a value between screens, show it instead. Chunk related
  information, separate unrelated. Budget roughly 4±1 items in working
  memory at once; if the design needs more, it's wrong. Reading order is
  top-to-bottom, left-to-right (LTR); highest priority first.
- **Error prevention and recovery.** List the mistakes users will make. For
  each: prevent (disable, hide, gate), warn (inline copy, never a modal
  unless destructive — an action whose effect cannot be reversed by a
  single, obvious undo; loss of unsaved input qualifies), or recover (undo,
  autosave, history). **Never use confirmation dialogs as a safety net** —
  confirmation fatigue makes them invisible; prefer reversibility.
- **Accessibility (non-negotiable).** Keyboard-only flow works end-to-end.
  Screen reader conveys the same information hierarchy as sighted use.
  Color is never the only signal. Targets meet 44×44 logical-px hit-area
  minimums. Motion is suppressible (`prefers-reduced-motion`).
- **Constraint inventory.** Existing design system, viewport range
  (smallest to largest realistic), performance budget, data realities (3
  items or 3,000?), platform conventions, team capacity to maintain the
  result.

The full written-output shape for this phase (ten labeled sections a UI
phase can consume) is in `references/ux-template.md`. Produce it before
moving on — do not carry an unwritten UX design into the UI phase.

## Frequency × Risk Matrix

| | Low risk | High risk |
|---|---|---|
| **High frequency** | One click, prominent, no confirmation | One click + undo. Never confirmation. |
| **Low frequency** | One click, can be buried | Gated by deliberate intent (explicit button, destructive-styled modal), undo if possible |

If a confirmation dialog looks necessary for a high-frequency action, the
UX is wrong — find the reversible alternative instead.

## The UI Phase (Translation Step)

UI is the *expression* of the UX design; patterns enter only now. For each
UX decision, score candidate UI expressions on: fit to the UX requirement;
whether the pattern's default behavior (clickable, dismissible, draggable)
matches what should be possible; information density at the target
viewport; cost of a misclick; consistency with the app's other patterns;
and scaling (3 items vs 300, 320px vs 3,840px).

If a pattern's default behavior conflicts with the UX requirement, in order
of preference: choose a different pattern whose default behavior matches;
explicitly suppress the conflicting default (make breadcrumbs non-clickable
when navigation is unsafe); or add an explicit safety mechanism (unsaved-
changes prompt) only if the conflicting behavior's value outweighs the risk.

## Orientation, Navigation, Action — Three Distinct Affordances

- **Orientation** — "where am I, what is this?" — static or near-static:
  labels, breadcrumbs (often non-interactive), titles, position indicators.
  Always visible when the user is in the state it describes.
- **Navigation** — "let me go elsewhere" — interactive: links, tabs, lists,
  search. Safe in clean states, hazardous in dirty states without
  safeguards.
- **Action** — "let me do something to this thing" — buttons, menus, direct
  manipulation. Always labeled; destructive actions always gated by intent.

Don't fuse them — a breadcrumb that's secretly a navigation control is two
affordances in one element and produces accidental navigation.

## Information Density and Viewport

A design correct at 1440px may be wrong at 5120px and at 360px. For every
layout decision, define the minimum viewport that must work, the target
viewport(s) where it should feel right, and the maximum before whitespace
becomes wasteful — then specify behavior across the range (stack, hide,
reveal, reflow, scale). The right answer depends on frequency-of-need and
available space, not a one-size rule.

## Anti-Patterns to Watch For

- **Design-for-demo.** Looks great empty; collapses at real-world data
  volumes.
- **Symmetry-over-function.** Two equal columns because it looks balanced,
  not because the content needs equal weight.
- **Pattern envy.** Copying a pattern from another app without verifying
  its UX requirements actually match.
- **Fused affordances.** One element serving orientation + navigation +
  action, producing accidental destructive clicks.
- **Confirmation dialogs as design.** "Are you sure?" compensating for a UI
  that doesn't prevent the mistake in the first place.
- **Capacity-bound design.** Designed only for the median case; 3-item and
  300-item realities ignored.
- **Treating the human's UI proposal as the brief.** They're describing a
  felt problem — diagnose it, don't transcribe their solution.

## Pre-UI Forcing Function

Before proposing any UI, complete this sentence with specifics: "When the
user is [exact state], they are trying to [job]. The information they must
see is [list]. The actions they must take are [list]. The actions they must
NOT accidentally take are [list]. The constraint that bounds the UI is
[list]." If you can't fill it in, you don't have a UX design yet — don't
propose UI.

## Pre-Implementation: The Six-State Sketch

Before writing UI code, sketch (ASCII, words, or low-fi mockup) each of:
default state at target viewport, smallest supported viewport, maximum
data volume, dirty state, empty state, error state. If any sketch reveals a
UX problem, return to the UX phase — don't patch it in code.

## Tells You Skipped the UX Phase — Return to It

Proposing a UI shape before writing the user's job; defending a UI choice
from convention ("breadcrumbs are clickable"); treating the user's UI
suggestion as the brief; shrinking or hiding a panel without naming the
information-need impact it costs; adding a confirmation dialog to "make it
safer"; solving for the median data case only; reasoning that starts at
"what component should we use"; the phrase "we could just…" entering the
design. Any of these: stop, return to the UX phase.

## Quick Reference — The Loop

1. UX phase: produce the written UX design (`references/ux-template.md`).
   No UI ideas yet.
2. UI phase: translate each UX decision to a UI expression, scored against
   fit, default behavior, density, error cost, consistency, scaling.
3. Sketch the six states.
4. Only then: implement.
5. After implementing: verify each state against the UX design. If any
   drifted, the implementation is wrong, not the UX.
