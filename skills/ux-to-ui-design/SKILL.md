---
name: ux-to-ui-design
description: Use when designing or modifying any UI — panels, layouts, navigation, forms, editors, dashboards, components, interaction patterns, or visual hierarchies. Use before proposing, planning, or implementing UI changes, including when reviewing UI work. Apply when a task involves screens, modes, states, or workflows even if the user did not use the word "design."
---

# UX-to-UI Design

## Overview

Act as a senior UX professional. Produce a UX design first — rigorous, defensible, expressed in user goals and task flows — then translate it into UI as a separate downstream step. Never start from a UI idea. Never let the user's UI suggestion bypass UX analysis; treat it as a hypothesis to test, not a brief to execute.

**Lay people cannot design UX.** That includes the human partner. They can describe symptoms, frustrations, and goals. They should not dictate solutions. When they propose a UI ("add a panel here"), translate it back to the UX question it implies, answer that, then derive the UI.

## When This Skill Fires

**Fires when the task touches any of:**
- Screen layout, panel structure, navigation
- Mode transitions (browse → edit, list → detail)
- New components or modifications to existing ones
- Forms, editors, wizards, modals
- Information density, visual hierarchy, spacing
- Empty/loading/error states
- Mobile/desktop responsiveness
- Accessibility considerations

**Does not fire when:**
- The task is purely mechanical (renaming a variable, fixing a typo in copy)
- A token-level change with no behavioral implication (color of an existing button to match the design system)
- Pure backend, plumbing, or refactor work with no UX surface change
- The UI is already locked by a design handoff being implemented faithfully (use `design-handoff` instead)

## Direction of Reasoning (One-Way)

```
User → Goals → Tasks → Information needs → Interaction needs → UX design → UI design → Implementation
```

Never reverse. Never start at UI and reason backwards. If you find yourself defending a UI choice, stop and re-enter at "User."

## The UX Phase (Required — Output Before Any UI)

Produce these artifacts as written reasoning. Skipping a section is the failure mode this skill prevents. If you cannot answer a section confidently, name the gap and ask.

### 1. Users and Contexts

- **Who** are the primary, secondary, edge-case users? (Power user, novice, occasional returner, accessibility user, mobile user.)
- **In what context** do they hit this screen? (Mid-task, exploring, recovering from an error, onboarding, demoing.)
- **What is their starting mental model** — what do they already believe about how this works?
- **What is their emotional state** — focused, frustrated, hurried, curious? Emotional state changes acceptable interaction cost.

### 2. Goals and Jobs-to-be-Done

- **Why** is the user here? Phrase as a job: "When I'm editing a hook, I want to confirm it does what I expect, so I can move on without breaking something."
- **What is success** from the user's point of view? Name the felt outcome, not the system event.
- **What is failure** from the user's point of view? Lost work, confusion, second-guessing, wasted clicks, missed information.

### 3. Task Flow (Boring Middle Included)

Walk the task end-to-end including the boring middle and the unhappy paths. Do not skip steps because they "feel obvious." The original failure mode is skipping the middle.

- Entry: how did they get here, what did they bring with them?
- Steady state: what are they doing 80% of the time on this screen?
- Decision points: where do they branch?
- Exit: how do they finish, save, abandon, or get interrupted?
- Recovery: what happens when they make a mistake?

### 4. State Analysis

A screen is not one thing. Enumerate every meaningful state and reason about each separately:

- **Clean / dirty** — are there unsaved changes?
- **Empty / partial / full** — how much data is present?
- **Loading / loaded / error / stale** — what is the data status?
- **Focused / browsing / idle** — what is the user's attention mode?
- **Permitted / restricted** — what can the user do?
- **Onboarding / experienced** — does the user know the patterns yet?

For each state, the UX answer can differ. A clean editor permits free navigation; a dirty editor must protect work.

### 5. Information Needs

For the user's state and goal, what must they see? Rank by criticality:

- **Must-see** — without this, the task fails or becomes unsafe.
- **Should-see** — improves confidence, reduces second-guessing.
- **Could-see** — useful when sought, not on by default.
- **Should-not-see** — clutter, irrelevant in this state, distracts from the task.

Apply progressive disclosure: must-see is always visible; could-see is one action away.

### 6. Interaction Needs

What must the user be able to do? Rank by frequency and cost-of-error:

- **High frequency, low risk** — keep within one action, no confirmation. (Type a character.)
- **High frequency, high risk** — keep one action but provide undo, never confirmation dialogs. (Delete a row.)
- **Low frequency, low risk** — one click, slightly buried is fine. (Open settings.)
- **Low frequency, high risk** — gated by intent (Done, Save, explicit click on a labeled control). Never accidental. (Delete account, change scope.)

### 7. Cognitive Load and Recall

- **Recognition over recall.** The user should not have to remember anything between screens. If they had to memorize a value, show it.
- **Chunking.** Group related information; separate unrelated. The eye should never scan past three unrelated regions to find one thing.
- **Working memory budget.** Roughly 4±1 items at once. If the UX requires holding more, the design is wrong.
- **Reading order.** Information is consumed top-to-bottom, left-to-right (LTR locales). High-priority info goes first.

### 8. Error Prevention and Recovery

- What mistakes will users make? List them.
- For each: prevent (disable, hide, gate), warn (inline copy, never modal unless destructive), or recover (undo, autosave, history).
- **Never use confirmation dialogs as a safety net.** Confirmation fatigue makes them invisible. Prefer reversibility.

### 9. Accessibility (Non-Negotiable)

- Keyboard-only flow must work end-to-end.
- Screen reader must convey the same information hierarchy as sighted use.
- Color is never the only signal.
- Targets meet hit-area minimums (44×44 logical px).
- Motion is suppressible (`prefers-reduced-motion`).

### 10. Constraint Inventory

Before proposing UX, list every constraint that bounds the design:

- Existing design system / component library
- Viewport range (smallest realistic to largest expected)
- Performance budget (initial paint, interaction cost)
- Data realities (will this list have 3 items or 3,000?)
- Platform conventions (macOS, Windows, web, iOS, Android)
- Team capacity to maintain the resulting complexity

## UX Design Output Format

Before any UI, produce a written UX design with these sections. This is the artifact the UI phase consumes.

```
USER & CONTEXT
- Primary user: [...]
- Context: [...]
- Mental model: [...]

JOB
- When [...], I want to [...] so that [...]

TASK FLOW
- Entry: [...]
- Steady state: [...]
- Exit / recovery: [...]

STATES
- [state]: [UX requirements for this state]
- ...

INFORMATION NEEDS (ranked)
- Must-see: [...]
- Should-see: [...]
- Could-see (on demand): [...]
- Should-not-see: [...]

INTERACTION NEEDS (ranked by frequency × risk)
- [...]

ERROR PREVENTION
- [mistake]: [prevention/recovery approach]

CONSTRAINTS
- [...]

UX DECISIONS
- [Decision]: [Reason rooted in the above]
```

Only after this exists do you move to UI.

## The UI Phase (Translation Step)

UI is the *expression* of the UX design. Now — and only now — patterns enter.

For each UX decision, evaluate candidate UI expressions. Score on:

1. **Fit to the UX requirement.** Does it deliver what the UX phase demanded?
2. **Default behavior alignment.** Does the pattern's standard behavior (clickable, dismissible, draggable, navigable) match what the UX phase says should be possible?
3. **Information density at target viewport.** Will it remain readable and useful?
4. **Cost of error.** What is the worst thing a misclick produces?
5. **Consistency.** Does this match other patterns in the app for similar UX needs?
6. **Scaling.** How does it behave at 3 items vs 300, 320px wide vs 3,840?

If the pattern's default behavior conflicts with the UX requirement, the design has three honest moves — in order of preference:

1. **Choose a different pattern** whose default behavior matches.
2. **Suppress the conflicting default behavior** explicitly (make breadcrumbs non-clickable when navigation is unsafe).
3. **Add an explicit safety mechanism** (unsaved-changes prompt, autosave) if the value of the conflicting behavior outweighs the risk.

Never choose a pattern then forget its default behavior was a hazard.

## Orientation, Navigation, Action — Three Distinct Affordances

Treat these as separate UX needs with separate UI answers:

- **Orientation** — "where am I, what is this?" — answered by static or near-static signals: labels, breadcrumbs (often non-interactive), titles, position indicators (`3 of 7`), color coding, icons. Always visible when the user is in the state it describes.
- **Navigation** — "let me go elsewhere" — answered by interactive elements: links, tabs, lists, search. Safe in clean states. Hazardous in dirty states without safeguards.
- **Action** — "let me do something to this thing" — answered by buttons, menus, direct manipulation. Always labeled. Destructive actions always gated by intent.

Don't fuse them. A breadcrumb that's secretly a navigation control is two affordances in one element and produces accidental navigation.

## Information Density and Viewport

A design correct at 1440px may be wrong at 5120px and wrong at 360px. For every layout decision:

- Define the **minimum** viewport that must work.
- Define the **target** viewport(s) where the design should feel right.
- Define the **maximum** viewport before whitespace becomes wasteful.
- Specify behavior across the range: stack, hide, reveal, reflow, scale.

Hiding a panel "entirely" is one option. So is showing it at 320px on 1440px and 480px on 4K. So is collapsing it to an icon rail with hover-expansion. The right answer depends on frequency-of-need and available space, not on a one-size rule.

## Frequency × Risk Matrix

Use this to decide how prominent an action should be:

| | Low risk | High risk |
|---|---|---|
| **High frequency** | One click, prominent, no confirmation | One click + undo. Never confirmation. |
| **Low frequency** | One click, can be buried | Gated by deliberate intent (explicit button, modal with destructive styling), with undo if possible |

If you find yourself adding a confirmation dialog for a high-frequency action, you have designed the wrong UX. Find the alternative.

## Anti-Patterns to Watch For

- **Designing for the demo, not the day-to-day.** The screen looks great empty. It collapses at real-world data volumes.
- **Treating "more visible" as "better."** Visibility costs attention. Things should be visible *when they earn it*.
- **Symmetry over function.** Two equal columns because it looks balanced — not because the content needs equal weight.
- **Capacity-bound design.** Designing only for the median case; ignoring 3-item and 300-item realities.
- **Pattern envy.** Copying a pattern from another app without verifying the UX requirements match.
- **Bolting modes onto layouts.** Reusing the same layout for browsing and editing because it's easier than designing two layouts.
- **Fusing affordances.** One element serving as orientation + navigation + action, producing accidental destructive clicks.
- **Confirmation dialogs as design.** Using "Are you sure?" to compensate for a UI that doesn't prevent the mistake.
- **Hiding-as-design.** Removing a panel without considering whether the user needed the information for orientation.
- **Treating the human partner's UI proposal as the brief.** They're describing a felt problem. Diagnose, don't transcribe.

## Worked Example — Hook Editing State

To make the reasoning concrete, here is one complete pass.

### UX Phase

**User & Context.** Primary user is a developer configuring hooks for a Claude Code project. They've selected a hook to edit. Their mental model: "this hook belongs to a specific project (or to my user account)." Emotional state: focused, mildly cautious — hooks affect every future session.

**Job.** When editing a hook, I want to change its definition with confidence that I'm editing the right one in the right scope, so I don't break other projects or my global setup.

**Task flow.**
- Entry: clicked a hook row in the list.
- Steady state: changing fields in the editor, glancing at the result.
- Exit: Done (commit), Cancel (discard), or get interrupted.
- Recovery: realized wrong hook → exit, pick another. Realized wrong scope → no recovery if accidentally clicked away.

**States.**
- Clean editor: free movement allowed.
- Dirty editor: changes must be protected.
- Editor with validation errors: cannot save, must fix.

**Information needs.**
- Must-see: hook identity (name, scope, event), the field being edited, validation feedback.
- Should-see: other hooks in the same scope (for orientation: "this is one of N").
- Could-see (on demand): hooks in other scopes, hook history, raw JSON.
- Should-not-see: marketing chrome, unrelated app navigation, ambient counts that don't pertain to this hook.

**Interaction needs.**
- High frequency, low risk: type in fields. One click.
- Low frequency, low risk: switch to a sibling hook in the same scope. One click, with dirty-state protection.
- Low frequency, high risk: change scope (project ↔ user). Gated by explicit control with confirmation copy ("This will move the hook to Global").
- Low frequency, high risk: leave the editor with unsaved changes. Gated by prompt or autosave.

**Error prevention.**
- Mistake: accidental scope switch mid-edit → prevent: scope is a deliberate explicit control inside the editor, not a sidebar click.
- Mistake: accidental project switch losing the edit → prevent: project navigation is suppressed or guarded while editor is dirty.
- Mistake: discarded edit on Done click → prevent: Done saves; Cancel discards; the words match the action.

**Constraints.** Existing design system (cc tokens). Desktop viewport 1100–3840px. Hook count realistically 0–30.

### UI Phase (Translation)

Given the UX above:

- The editor must be the dominant region; it carries the must-see and high-frequency interactions. → Editor occupies the majority of width.
- "This is hook X in scope Y" is orientation → static breadcrumb in the editor header, non-clickable, no hover affordance.
- Sibling-hook navigation is should-see, low-frequency-low-risk in clean state, must be guarded in dirty state → a slim sidebar listing sibling hooks (name only, scope grouping), readable at the chosen width, with dirty-state guard (autosave or prompt). Critically: this sidebar appears only if the chosen width allows readable rows; otherwise sibling navigation moves to a header-level dropdown or is hidden entirely at small viewports.
- Project navigation (a hazard during edit) → the project rail is hidden or made inert while the editor is dirty.
- Done / Cancel are gated controls in a stable place (header, right-aligned). Done is high-emphasis; Cancel is low-emphasis text.
- Empty state: zero hooks → no editor, only an inviting "Add your first hook" prompt.
- Error state: invalid field → inline error under the field, save button disabled, no modal.

Each UI choice traces back to a specific UX requirement above. None were chosen by convention.

## Defining Load-Bearing Terms

- **Focused state.** A state in which the user is actively producing output (editing, composing, configuring) such that involuntary state change would cost them work or attention to recover. Editing a hook is focused; viewing the hook list is not.
- **Dirty state.** The current view contains user input or changes not yet persisted. The boundary case (user typed then deleted) counts as dirty until persistence resets.
- **Destructive action.** Any action whose effect on user state cannot be reversed by a single, obvious undo. Loss of unsaved input qualifies.
- **Orientation.** Information that answers "where am I, what is this, what state is it in." Inert by default; if interactive, the interactivity must serve a separate UX need that has been justified.
- **Navigation.** A user-initiated change in what they're looking at or working on. Always involves leaving the current task or context, even briefly.

## Pre-UI Forcing Function

Before proposing any UI, write the following sentence and fill the blanks:

> "When the user is [exact state], they are trying to [job]. The information they must see is [list]. The actions they must take are [list]. The actions they must NOT accidentally take are [list]. The constraint that bounds the UI is [list]."

If you cannot complete this sentence with specifics, you do not yet have a UX design. Do not propose UI.

## Pre-Implementation Forcing Function

Before writing UI code, sketch (in ASCII, words, or a low-fi mockup) the UI for:

- The default state at your target viewport
- The state at the smallest supported viewport
- The state at maximum data volume
- The dirty state
- The empty state
- The error state

If any of these sketches reveal a UX problem, return to the UX phase. Do not patch in code.

## Red Flags — Stop and Restart from UX

- Proposing a UI shape before writing the user's job
- Defending a UI choice from convention ("breadcrumbs are clickable")
- Treating the user's UI suggestion as the brief
- Shrinking or hiding a panel without naming the information-need impact
- Adding a confirmation dialog to "make it safer"
- Solving for the median data case only
- Treating "more visible = better"
- Reasoning starts at "what component should we use"
- The phrase "we could just…" entering the design

All of these mean: stop, return to the UX phase, produce the artifact above.

## Quick Reference — The Loop

1. UX phase: produce the written UX design artifact. No UI ideas yet.
2. UI phase: translate each UX decision to a UI expression, scoring against fit, default behavior, density, error cost, consistency, scaling.
3. Sketch the six states (default, smallest, max-data, dirty, empty, error).
4. Only then: implement.
5. After implementing: verify each implemented state against the UX design. If any drifted, the implementation is wrong, not the UX.
