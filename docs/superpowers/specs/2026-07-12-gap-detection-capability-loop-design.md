# Gap Detection & Capability Improvement Loop — Design

**Date:** 2026-07-12
**Status:** Draft for human review
**Prior art:** `2026-07-07-ai-agent-team-design.md` (roster, permissions, gates — unchanged),
`2026-07-09-org-skill-layer-design.md` (`skills/` as the canonical org skill layer, house
authoring standard), `2026-07-10-decision-discipline-design.md` (two-questions block, spec
critic), `PARKING-LOT.md` (the promotion-trigger pattern this design reuses).
**Review:** spec panel convened 2026-07-12 (discussion mode, full spec roster). All eight
prioritized recommendations are incorporated; the panel's keep-or-cut question on the
charter-misfit flag is decided, with reasoning, in §2. A second panel (debate mode, same
roster, 2026-07-12) stress-tested the revised spec: its recommendations 1–8 and 10 are
applied throughout, and its contested point on §5's process depth is resolved as
*provisional process* — written now, expected to be revised by first use (see §5).

## Goal

Give the team a way to notice the gaps it cannot see today — above all missing domain
expertise — record them as durable evidence, keep the current task moving through a
sanctioned fallback instead of stalling or silently shoehorning, and let the human promote
recurring gaps into new capabilities built through the team's existing software route.

No new agents. No new routes. No self-granted capabilities. The loop's product is
*evidence and proposals*; every act of capability creation stays behind a human decision.

## Motivating scenario

An engineer uses the team to build bank- and credit-card-reconciliation tools for a
finance team. The engineer is not an accountant. Nothing in the current design notices
this: the architect specs confidently, the builder builds, the verifier's tests pass — and
the tool mishandles outstanding-check aging, NSF reversals, and cutoff conventions,
because nobody in the pipeline knew those norms exist. The missing knowledge is invisible
to the agents missing it, and to a human operator who is not Jay. The same failure
generalizes to any coworker who shares this team and hands it a task in a domain the
skill layer does not cover.

The insight that shapes this design: recognizing *that* a field is specialized does not
require knowing the field. "Correctness here is judged by an accountant's norms, not by
this spec" is detectable by a non-accountant — it is what a good engineer means by
"I should talk to an accountant before building this."

## Non-goals

- **No capability-steward agent.** A steward sits where the evidence isn't, recreates the
  detection problem at consultation time, and holds no unique permissions — by this
  team's own standard that is a prompt, not an agent.
- **No new dispatch route.** Capability work is a normal software task on this repository
  (spec → gate → build → verify → review, spec critic included).
- **No inline healing.** A gap discovered mid-task is never closed mid-task.
- **No automatic promotion.** No agent initiates capability work; the human does.
- **No multi-install sync machinery.** Gap records flow between installs by ordinary git
  (a human opens the PR). Nothing watches or merges automatically.
- **No changes** to roster, models, permissions, hooks, routes, or cost-accounting
  mechanics. Two agent files gain short instruction blocks; that is the entire footprint
  on the installed team.

## Design overview

Two sensors feed one handling procedure:

1. **Domain sensor** (architect, at investigation time): "is this a specialty domain, and
   do we hold a domain skill for it?" — catches unknown-domain work before a spec exists.
2. **Friction review** (orchestrator, at every gate): a mandatory `gaps:` line forces a
   review of the task's accumulated friction — policy blocks, wrong-tool reports,
   re-routes — at the moments the evidence actually exists.

Detected gaps trigger three orchestrator duties, never a stall: a **fallback** that keeps
the current task moving informed, **disclosure** to the human on an existing gate, and a
**gap record** written by the scribe to `docs/gaps/`. Promotion of a recorded gap into a
capability task is human-only. The capability itself is almost always a **skill** —
usually a *domain skill*, a new artifact class defined in §5 — built and validated
through the existing software route.

## 1. Domain sensor (architect)

Add to the architect's "Investigate before you design" section (normative text, ~13 lines):

> As part of investigation, apply the **practitioner test**: would a practitioner of some
> field reject output that merely satisfies this spec? If yes, correctness here is judged
> by that field's norms, not by the spec alone — true of accounting, tax, payroll, legal,
> medical, and insurance work, and equally of unlicensed fields with hard norms
> (logistics, actuarial pricing, manufacturing tolerances). When the test fires, Glob the
> installed skills for a `domain-<field>` skill. If one exists, invoke it and carry its
> constraints into the spec and plan explicitly — the builder cannot load skills, so
> **the plan is the carrier** of domain constraints, and every domain-constrained plan
> must state: domain questions this plan does not answer are stop-and-report to the
> orchestrator, never the builder's own judgment call. If no skill exists, declare
> `DOMAIN GAP: <field>` in your report, name the norms you believe are load-bearing (even
> approximately — "there are matching and cutoff conventions I don't know"), and do not
> write the spec until the orchestrator supplies researcher-gathered domain input. Label
> every acceptance criterion that rests on that input `domain-uncertified`.

Domain skills are named `domain-<field-slug>` (e.g. `domain-bank-reconciliation`) so the
existence check is a Glob, not a judgment call.

## 2. Charter-misfit detection — decided: no per-specialist flag

The panel asked for one concrete charter-misfit instance not already covered by existing
rules, and none survived inspection: policy blocks are covered by the builder's
stop-and-report discipline, unverifiable criteria by the verifier's UNCHECKED verdicts,
missing inputs by the scribe's missing-input rule, and malformed dispatches by the
dispatch guard. Specialist-level charter misfit is pre-empted by routing by construction;
when routing genuinely fails, the specialist cannot see why — the evidence lives with the
orchestrator.

**Decision: cut the planned nine-file shared `MISFIT:` block.** What replaces it:

- The specialists' existing stop-and-report rules remain the raw signal — unchanged.
- The **gate `gaps:` line** (§3) is an acknowledgment and a prompt, not a guaranteed
  sensor: at every gate the orchestrator must review the task's accumulated friction and
  either write `gaps: none` or name the gap. It runs at the right moments (post-friction,
  evidence in context) and costs nothing new — but a mandatory recited field habituates
  (the same principle this team's decision discipline already records against recited
  caveats), so fit-gap detection is honestly **best-effort**. The domain sensor (§1) is
  the primary sensor of this design; the gaps line raises the odds that fit friction gets
  noticed while avoiding what a nine-file flag would have risked: training every agent
  toward false-positive flagging, the documented besetting risk of this team.

This also removes the need to extend the drift test (no new shared block exists) and cuts
the new-instruction budget roughly in half.

## 3. Orchestrator gap handling

Add a "Gap flags" section to the orchestrator (normative text, ~16 lines):

> **Gap flags.** Two signals name a capability gap: an architect `DOMAIN GAP`, or your own
> gate-time review of task friction (repeated policy blocks, work no specialist fits,
> a route that fights the task's shape). Apply investigate-first before accepting either:
> *misfit means the wrong kind of work; hard means the right kind, difficult — hard is
> never a gap.* On a confirmed gap, never stall and never build capability mid-task:
> 1. **Fallback.** For a domain gap, dispatch the researcher (sonnet; opus for regulated
>    or high-stakes domains) to gather sourced domain knowledge for this task, labeled
>    *uncertified*, and attach it to the architect/builder dispatch context. For fit
>    friction, re-route to the closest specialist and make the reviewer pass mandatory
>    regardless of tier.
> 2. **Record.** Assign the record's identity yourself — `<kind>-<slug>`, slug at field
>    granularity (`payroll`, never `payroll-withholding`) — then dispatch the scribe on
>    `haiku`: read `<repo>/docs/gaps/README.md` (repo path from the manifest) and write
>    one gap record per its schema under the identity you assigned. If the manifest is
>    missing or unreadable, have the scribe write a best-effort record — kind, task, gap,
>    fallback — to the current project's `docs/gaps/` instead, and disclose the degraded
>    path at the gate.
> 3. **Disclose.** Every gate summary carries a mandatory line: `gaps: none` or
>    `gaps: <record filenames>`. A task that proceeded on uncertified domain input says
>    so at each gate, and its gate summary recommends human or domain-expert review of
>    the acceptance criteria themselves.
> In the closeout report, gap-handling dispatches (researcher backfill, added reviewer
> passes, scribe gap records) appear as their own labeled rows.

The `gaps:` line is deliberately mandatory even when empty — a dropped flag becomes a
visible protocol violation rather than a silent loss, the same pattern as the manifest
build line at session start.

The session-start manifest ritual itself extends by one clause (~3 lines): after the
build line, Glob the current project's `docs/gaps/` and, if any records exist there,
report "`N` gap records in this project await upstreaming." Degraded-path strays stay
visible every session until a human moves them; records count toward promotion only once
they are in the canonical repository's main (§4).

## 4. Gap records — `docs/gaps/`

One file per detection, in this repository (or the project's `docs/gaps/` on the degraded
path): `docs/gaps/GAP-<YYYYMMDD>-<kind>-<slug>.md`. A directory of small files merges
cleanly across installs, gives each gap a stable identity (the `<kind>-<slug>` pair), and
survives schema evolution (each file states its schema version).

`docs/gaps/README.md` (repo content, not installed instruction text) defines schema v1:

```
# GAP-<YYYYMMDD>-<kind>-<slug>
- schema: 1
- kind: domain | fit | permission/tool | process
- detected: <date> / <project> / <detector: architect domain check | orchestrator gate review>
- task: one line on what was being attempted
- gap: what was missing
- fallback: what the team did instead (e.g. "uncertified researcher backfill, sources cited in spec")
- recurrence: filenames of earlier records with the same <kind>-<slug>, if any
- status: open | promoted → <spec/ticket path> | declined — <reason>
```

Semantics:

- **Identity:** same `<kind>-<slug>` = same gap. The orchestrator assigns the slug in
  the scribe's dispatch, at field granularity (`payroll`, not `payroll-withholding`) —
  coarse slugs err toward over-linking, which is the safe direction for a promotion
  trigger. The scribe lists the directory and links `recurrence:` to existing records
  under the same identity.
- **Evidence, not workflow.** A record freezes when its status leaves `open`: `promoted`
  records point at the spec or ticket where the work is tracked (Asana per org
  discipline, via the ticketer, when the human wants it tracked); `declined` records keep
  the reason. The gap directory never becomes a second ticket system.
- **Declined is not terminal — the reason carries forward.** A new detection with a
  previously-declined identity is still logged (detection and decision are separate
  concerns), links the declined record in `recurrence:`, and is presented at the gate
  with the decline attached: `gaps: GAP-<date>-<id> — note: declined <date>, reason:
  <reason>`. It re-opens the question only when the human says the stated reason no
  longer holds; the declined record itself is never edited or deleted.
- **Flow-back across installs:** a coworker's install writes records into their own clone
  (their manifest points there); their human opens an ordinary PR to this repository.
  Promotion decisions happen only against canonical main, and **a record not in canonical
  main does not exist for promotion purposes** — local and degraded-path records count
  for nothing until merged, which is why the session-start ritual (§3) keeps strays
  visible.
- **Relation to `PARKING-LOT.md`:** the parking lot stays human-curated deferred *ideas*;
  `docs/gaps/` holds machine-written observed *evidence*. An idea may cite gap records as
  its promotion trigger.

## 5. Promotion policy

- **Human-only.** Default trigger: a second record with the same `<kind>-<slug>`, or the
  human explicitly saying "close this one." No agent initiates capability work.
- **Closing a gap is a normal software task on this repository** — spec → gate → build →
  verify → review, spec critic included. No new route exists for it.
- **Skills over agents.** A new agent requires a genuinely new permission surface plus
  explicit human approval — the same bar as today. Expected volume: nearly all
  promotions produce a skill.
- **Permission/tool gaps** are human-decided, always: the team may draft the proposal,
  never self-grant.
- **Process gaps** (the route itself misfits a class of work) promote to an orchestrator
  amendment — the team may draft it; it lands only through the human gate, like every
  amendment so far.

### Domain skills — a new artifact class

Domain skills encode what is true in a field (reconciliation norms, matching rules,
controls), not how to work. They get class-specific acceptance criteria, on top of the
house authoring standard.

**This process is provisional pending first use.** The first real promotion is expected
to revise this subsection, and doing so is an amendment, not a violation. It is written
down now so that expert involvement cannot silently degrade into approval theater — not
because the details are settled ahead of any instance.

1. **Examples first.** Before the skill is built, the named domain expert supplies
   concrete worked examples — real edge cases, relayed by the human from a short
   conversation (the expert does not use this tooling). For reconciliation: actual NSF
   scenarios, month-end cutoffs, outstanding-check aging cases.
2. **Built to the examples.** The skill is written so each expert example is explicitly
   encoded; the researcher's cited sources supply the surrounding structure.
3. **Sign-off = example verification.** The expert (via the human) confirms their own
   examples are correctly encoded — a review an expert can actually perform reliably,
   unlike reading a skill document cold. Recorded in the skill:
   `validated-by: <name>, <date>, examples-verified, review-by: <date>`. The `review-by`
   date exists because domain norms change (tax law, annually); a skill past its
   `review-by` date is consumed as unvalidated until re-verified.
4. **No expert reachable:** the skill may still ship, labeled
   `validated-by: none — citations only`. The label is restated wherever the skill is
   consumed (spec, plan, gate summaries), and the gap record stays `open` rather than
   closing — an unvalidated skill *mitigates* a gap; it does not *close* one.
5. **Citations mandatory** for every normative claim not covered by an expert example.
6. **Consumption is situational via the plan.** Domain skills are never preloaded. The
   architect (which holds the Skill tool) invokes them at design time; the plan carries
   the constraints to the Skill-less builder as explicit tasks and acceptance checks —
   and states that domain questions the plan does not answer are stop-and-report, never
   the builder's own judgment call (§1).

A domain skill is memoized research: the researcher can answer per-task, but that pays
the cost every task and the answer evaporates. The skill is that research cached, curated
to the house standard, and validated once by someone who actually knows.

## 6. Testing & shakedown

No new drift test is needed (§2 removed the only shared block). `install.sh` is
untouched — `docs/gaps/` is repo content, and both agent-file changes ride the existing
checksum/manifest machinery.

Add five scenarios to the manual behavioral-validation procedure. They are ranked, not
equal: **scenario 3 is load-bearing** — it tests the discriminator, the highest-risk
behavior in the design, and should re-run after any change to the orchestrator's Gap
flags text. Scenarios 1–2 matter at first domain contact; 4–5 are documentation-grade.

1. **Domain-positive:** a payroll-withholding-calculator task → the architect declares
   `DOMAIN GAP: payroll` *before* writing a spec; researcher backfill runs; the gate
   discloses uncertified input and recommends criteria review; a gap record appears.
2. **Domain-negative:** the same task with a `domain-payroll` skill installed → no gap
   declared; the skill's constraints appear in the plan.
3. **Hard-but-in-charter negative:** a genuinely difficult refactor entirely inside the
   team's competence. Objective pass condition: every gate summary line reads exactly
   `gaps: none` and no `GAP-*.md` file exists anywhere after the run.
4. **Declined promotion:** the human declines a recorded gap → the record freezes as
   `declined` with the reason; no capability work starts.
5. **Degraded logging path:** manifest absent → the record lands in the project's
   `docs/gaps/`, and the gate summary discloses the degraded path.

## 7. Size audit

New installed instruction text: ~13 lines (architect) + ~19 lines (orchestrator,
including the session-start ritual clause) ≈ 32 lines, against the ~40-line ceiling this
design set for itself — the second panel's amendments spent most of the remaining slack,
which is itself a signal to hold the line here. New repo content:
`docs/gaps/README.md` (schema) and this spec. New agents: zero. New routes: zero. New
hooks: zero. Every prior amendment to this team was incident-driven; this is the first
speculative one, which is why it ships at minimum viable size — the loop's own gap
records are the evidence that will justify (or refute) growing it.
