# Decision discipline: two questions + a second-opinion spec critic

**Date:** 2026-07-10
**Status:** Design revised (v2.1) after spec-panel review and re-panel verification; ready for implementation plan
**Related:** the `AskUserQuestion` gate-picker fix already applied to `agents/orchestrator.md` (2026-07-09 session) is the downstream half of this design.

## Revision note — spec-panel review (2026-07-10)

v1 was reviewed by the spec roster (Wiegers, Adzic, Cockburn, Fowler, Nygard, Newman) in blind, dispatched mode. The panel converged on two semi-fundamental findings and six mechanical ones. v2 resolves all eight:

- **Detection hole (the showstopper):** v1's trigger only re-judged decisions the architect *chose to list* — so a decision mis-triaged as trivial (the actual incident) never entered the pipeline. Closed by requiring the architect to inventory **every** decision (trivial ones one line each) *and* having the critic survey the **raw spec** independently.
- **Independence was asserted, not real:** a same-lineage Claude critic likely shares the architect's binary-with-default bias. v2 stops claiming unqualified "independence," names it a *differently-tiered second opinion (partial independence)*, and adds a **degrade-and-warn** path so a gate never presents as checked when it isn't. True lineage independence (cross-vendor) stays parked.
- **Mechanical:** model rule made total and non-contradictory; a visible terminal state on loop exhaustion; mandatory critic re-review per rework pass; a second held-out validation scenario plus a negative example and all tells exemplified; a drift test across the inlined copies; explicit reviewer mode-signal and the read-only caveat named.

The Cockburn tension is explicit in v2: the fixes add rigor, so each is kept proportional (a one-line inventory entry, not a mini-spec, for trivial decisions) to avoid reintroducing the over-process the Trivial-tier amendment removed.

## Re-panel verification (2026-07-10)

v2 was returned to the three experts who raised the showstoppers (Cockburn, Nygard, Newman), continued with their prior critiques in context. **All three confirmed their showstopper closed** — the detection hole ("closed the right way, defense in depth"), the terminal state ("a defined terminal state on the exact failure path"), and independence (Newman withdrew his "don't ship" position: v2 "claims only what it can support"). Their refinements converged on one recursive insight: *a warning that fires constantly and costs nothing to bypass is indistinguishable from no warning* — the very anti-pattern this design targets, aimed back at its own flags. v2.1 folds them in: flags fire only on real degradation and are **load-bearing** (residual findings become the gate's decision content via the picker, not a banner); the "three independent paths" claim is corrected to *one omission-catch plus two enumeration-dependent audits*, the redundancy treated as a hypothesis under test; per-pass re-review is narrowed to the specific findings; a bounded retry precedes any critic-non-completion flag; the raw-spec survey gets an auditable coverage rule; the drift test normalizes whitespace; and cross-vendor moves from parked to a triggered roadmap item.

## Problem

In a live session (`2026-07-09-174918-build-a-cli-tool…`), the architect faced two design decisions on a CSV→JSON tool — value typing, and empty-input handling. For each it produced a **binary with a default** ("keep everything as strings, or infer types — recommend strings") and handed it up as an approve-as-is recommendation. Both binaries were false: when the human pushed back, a plainly better third option surfaced within seconds (strings-by-default **plus** an opt-in `--infer-types` flag; and splitting header-only input from genuinely-empty input). Those answers were *derivable* — no human values were needed — but the architect never worked the decision far enough to find them, and the human had to intervene twice. That cost an extra architect amendment (the most expensive step in the run) and two gate round-trips.

Two distinct faults, on two independent axes:

1. **Importance, undervalued.** The typing decision *mattered* (it set an output-data contract) but was treated as a throwaway default. This was a **Small**-tier task, so a "only big tasks get scrutiny" rule would miss it — the consequential decision hid inside a small task, and it was never even surfaced *as* a decision.
2. **Completeness, stopped short.** Even granting it mattered, the architect presented an unworked binary and dressed it as done rather than trying to dissolve the tradeoff.

The human was the only thing catching either fault. This design moves both catches into the team — and, critically, catches fault #1 (the undervalued-and-unsurfaced decision), not only fault #2 (the visible bad binary).

## Goals

- Give agents a cheap, always-on way to tell a decision that *matters* from one that doesn't, and to notice when they've *stopped short* on one that matters.
- Make consequential design decisions get *worked* (not defaulted) before they reach the human, and give the human a second-opinion check that this happened — without the human being the check, and without the check depending on the same judgment that failed.
- Be honest about how much independence that second opinion actually provides.
- Do all of it without reintroducing the over-process the Trivial-tier and investigate-first amendments removed: **trivial tasks and trivial decisions pay at most one line of inventory each, and fire no critic.**

## Non-goals

- Not a team-wide rollout. This targets the architect's spec, where the failure happened. (See Parking Lot: team-wide decision discipline.)
- Not a cross-vendor critic. This pass achieves only *partial* (capability-tier) independence with a different Claude model; genuine lineage independence is deferred. (See Parking Lot: cross-vendor critic, and "On independence" below.)
- Does not change the human-approval GATE model, the tiers, or the routes — only what reaches a gate and how well-worked it is.

## The two questions (canonical vocabulary)

The discipline is two questions an agent asks about every decision it makes. The word **GATE** stays reserved for human-approval moments; these are questions an agent asks itself, not gates.

**1. Does this matter?** Most decisions don't — make those well and move on, no litigating. A decision *matters*, and has to be genuinely worked, when it:
- sets a contract someone downstream depends on (output shape, data semantics, exit codes), or
- touches correctness, data-integrity, or security, or
- is hard to reverse, or grows/shrinks scope, or
- is one two good engineers would plausibly resolve differently.

Everything else — which stdlib module, file layout, naming — you decide well and move past. **Trivial never means careless;** it means don't hold a hearing over it.

*Worked positive example:* CSV value typing sets the output data contract → **matters**. *Worked negative example:* choosing `csv` stdlib module vs. hand-parsing, where both produce identical output and the choice is internal and reversible → **does not matter**; decide (stdlib `csv`, it handles quoting) and move on in one line. The negative example is as important as the positive: "does this matter?" must be able to say **no**, or it becomes the over-process this design exists to avoid.

**2. Did I actually work it?** For the decisions that matter, the failure isn't getting it wrong — it's stopping short and dressing it up as done. You've **stopped short** when you catch yourself:
- presenting **a binary with a default** — *"strings or inferred types, recommend strings"* when the real answer was strings-by-default **plus** an opt-in `--infer-types` flag that dissolves the tradeoff;
- **meeting a requirement by quietly shrinking it** — *acceptance criterion says "handles malformed input"; you quietly redefine "malformed" to mean only empty files and call it met*;
- **pushing the hard part to a "follow-up"** — *"type coercion is the downstream consumer's problem"* — offloading the actual difficulty instead of solving it;
- **writing a label where an argument belongs** — *"strings by default: simpler and predictable"* with no reasoning under the label.

When a decision matters, **work it**: first try to dissolve the binary; if it's genuinely open, get a second opinion, or sketch a few independent designs and judge them separately, then together. What is *still* a real either/or after that — and only that — goes to the human.

When a decision that mattered got stopped short, there are two ways back: **finish** it (the approach was right, just incomplete) or **rework** it (the shortcut was the framing, and it needs a better frame).

## On "independence" (honest framing)

The second-opinion critic runs a **different Claude model tier** than the architect ran. This buys *capability* diversity and *context* independence (a fresh reader with no attachment to the first framing) — but **not lineage independence**: Fable and Opus share a training and alignment pipeline and can share the same reasoning biases, including the binary-with-default habit this design targets. So the critic is a genuine second opinion, not an independent oracle. Two consequences are baked into the mechanism: (a) detection does **not** rest on the critic alone — but be precise about how much this buys. The architect's inventory and the orchestrator's audit only inspect decisions that were *enumerated*, so the one path that catches a decision never surfaced *as* a decision is the critic's raw-spec survey. And two of the three paths are the same model family running the same Question-1 criteria, so identical vocabulary may *correlate* their judgment rather than decorrelate it. Treat the multi-path redundancy as a **hypothesis under test** (Acceptance criteria 5b), not a banked reduction in blast radius. (b) when no distinct model is even available, the mechanism **degrades and warns** rather than presenting a same-model pass as if it were independent. True lineage independence (a cross-vendor critic) is the parked upgrade — now with a defined promotion trigger (see Out of scope).

## Encoding approach

**Inline, each agent self-contained (Approach A).** The two-questions vocabulary is added as short prose to each agent's own `.md`, because no agent in this team loads a shared reference doc mid-dispatch — a pointer risks being skipped. To contain the drift this creates, the **canonical two-questions block is delimited by markers** (`<!-- two-questions:start -->` … `:end -->`) in each file, and a test asserts the three copies match after trailing-whitespace normalization (identical modulo cosmetic whitespace, so a stray trailing space can't red the build; see Acceptance criteria #6). This design doc is the canonical source. Note this guards the shared *prose*, not the role-specific Question-1 *application logic* in each agent — that logic lives in three places and only one is drift-protected, so keeping the criteria aligned across roles is a standing review responsibility the test cannot enforce.

## Changes by component

### Architect (`agents/architect.md`)

1. Add the two-question reflex to the architect's process, applied to every consequential decision **regardless of tier**.
2. Sharpen the existing "Resolve, don't escalate" line with the *why*: you resolve most decisions because working them dissolves the false binary; you escalate only what is genuinely still either/or after that.
3. **Full decision inventory in the report** — the edit that closes the detection hole. The architect lists **every** decision it made, not only the ones it judged important:
   - *Consequential* decisions get a full entry: the decision, options considered, the chosen one *and the reasoning under it*, and whether it is resolved or a genuine either/or for the human.
   - *Trivial* decisions get **one line each**: the decision and `not consequential: <why>`.
   This is deliberately cheap for trivial calls, but it makes the architect's *triage itself* auditable — a second party can now scan whether "trivial" was applied honestly, which a "list only what matters" format structurally cannot.
4. Explicitly forbid handing the human a decision the architect has not first tried to dissolve; the `--infer-types` case is the worked example.

### Reviewer (`agents/reviewer.md`)

1. Add a **spec-critique mode**. When dispatched against a spec, the reviewer does two things: (a) **surveys the raw spec text section by section** for consequential decisions the architect did *not* surface as decisions at all — recording, for each section, either the decisions found or an explicit "no consequential decision here," so the survey's coverage is auditable rather than a vague once-over (the fault-#1 catch, and the only path that does not depend on the architect having enumerated the decision; it does not trust the inventory to be complete), and (b) audits the flagged decisions through Question 2's tells.
2. **Verdict must argue, not label.** For each consequential decision the verdict is **worked** or **stopped-short**, and a "worked" verdict must state *why the decision survived scrutiny* — not merely "no tell fired." (A bare "no tell fired → worked" is itself tell #4, the label-where-an-argument-belongs failure.)
3. The spec-critique instructions must be **fully self-contained in the reviewer's body** — the preloaded `code-review` skill is code-specific. Update the reviewer's description/frontmatter to reflect the bimodal role (code review *and* spec critique), and require the **dispatch to name the mode explicitly** (artifact type is not a reliable implicit signal).
4. **Read-only caveat (named, not hidden):** the reviewer retains `Bash` from its code-review role, so "never rewrites the spec" is enforced by instruction, not by tool surface. This is an accepted limitation of reusing the reviewer; the plan must not claim structural enforcement it doesn't have.

### Orchestrator (`agents/orchestrator.md`)

1. **Trigger — audit the inventory, re-triaging every trivial line.** After the architect returns, the orchestrator reads the **full** inventory and independently applies Question 1 to *every* entry — **re-triaging each one-line "trivial" call**, not sampling them (they are one line each; a defined re-triage has teeth, an undefined "spot-check" decays to a glance). If the orchestrator's read and the architect's disagree on whether a decision matters, **the orchestrator's judgment wins** and the critic is dispatched. Honest framing of the paths: the inventory audit and this re-triage can only inspect decisions the architect *enumerated* — the true catch for a decision never surfaced *as* a decision is the critic's raw-spec survey (Reviewer 1a). So detection is **one omission-catch plus two enumeration-dependent triage-audits**, not three interchangeable paths.
2. **Model rule — total and ordered.** Tier strength order is `haiku < sonnet < opus < fable`. The critic runs a **different model than the architect ran, one tier stronger**; if the architect ran the strongest tier (`fable`), one tier weaker (`opus`). This covers every architect model (including `sonnet`/`haiku` amendment runs), always yields a distinct model, and is a single consistent rule. **Degrade-and-warn:** if no distinct model is available, dispatch the same model and flag the gate `independence: degraded — critic ran the architect's model`. This flag fires **only on the degraded path** — a clean differently-tiered pass carries no independence banner, because a caveat recited on every gate trains the human to ignore it (the honest framing lives in this doc, not in every gate message).
3. **Routing — targeted re-review, and a load-bearing end.** "Stopped-short" findings loop back to the architect (its call: finish or rework); after each pass **the critic re-checks only the specific findings it raised** — confirming the named tells are cleared, not a full raw-spec re-survey each pass. Bounded by their own **max-two-loop** counter (a separate instance of the rule, not the shared build-phase counter). **Terminal state (load-bearing, not a banner):** if the critic still returns stopped-short after two passes, the orchestrator does not proceed silently *and* does not merely annotate — it takes the outstanding findings to the human **as the gate's decision content, through the `AskUserQuestion` picker** ("here are the N still-contested points; choose"), forcing engagement rather than a click past a warning. Fail-visible, never fail-open.
4. **Critic non-completion — one retry, then a load-bearing flag.** If the critic dispatch errors or times out, retry it **once** (separating a transient hiccup from real unavailability). If it still does not complete or is skipped, the gate presents the decisions **as unreviewed** — through the picker, flagged `critic did not complete` — never as checked when the check did not run.
5. **Gate presentation.** Genuine either/or decisions that *survive* the working-it pass go to the human through the `AskUserQuestion` picker (the already-applied fix), recommended option labeled — never folded into an "approve as-is" paragraph. Degraded gates (items 3, 4) use the *same* picker with the residual findings as the options, so a flagged gate always costs the human a real choice, not a rubber stamp.
6. **Cost + tier consistency.** The extra critic dispatch and any rework are real added spend on *consequential* specs only, visible per-dispatch in the closeout report. **Trivial-tier tasks, and Small tasks with no consequential decision, fire no critic and pay only the one-line-per-decision inventory cost.**

## Relationship to the applied picker fix

The 2026-07-09 fix wired `AskUserQuestion` into the orchestrator's Gates so genuine either/or decisions are put to the human as a choice rather than buried in a recommendation. That is the **downstream** half — *how* a decision reaches the human. This design is the **upstream** half — ensuring only *worked* decisions get there, and that a consequential-but-unworked (or unsurfaced) decision is caught and sent back first. Together: surface every decision → catch undervalued and stopped-short ones via inventory + audit + critic → present only genuine survivors, as a real choice.

## Acceptance criteria

1. The architect's report inventories **every** decision: consequential ones with options/chosen/reasoning/resolved-or-either-or; trivial ones one line each with `not consequential: <why>`. The two-question reflex applies regardless of tier.
2. The reviewer has a self-contained spec-critique mode that (a) surveys the raw spec for unsurfaced consequential decisions and (b) audits flagged ones; each "worked" verdict states why the decision survived; its frontmatter/description reflect the bimodal role; the dispatch names the mode explicitly; the read-only-is-prompt-only caveat is documented, not overclaimed.
3. The orchestrator re-triages **every** inventory line (not a sample), applies Question 1 independently with its own judgment winning on disagreement, dispatches the critic per the total model rule (one tier stronger, or one weaker from fable; degrade flag only on the degraded path), re-checks only the specific findings on each rework pass, retries a non-completing critic once, and on two-pass exhaustion or non-completion presents the residual findings to the human **as the picker's decision content** (load-bearing, not a banner), never a silent pass.
4. No critic fires for Trivial-tier tasks or Small tasks with no consequential decision; the degrade-and-warn path flags reduced independence at the gate; added cost is visible per-dispatch.
5. **Validation is not proof-by-origin.** Three checks: (a) replay the origin transcript — the typing decision is caught pre-human and worked into the opt-in-flag design; (b) a **second, independently-constructed scenario of a different task shape**, in which a consequential decision the architect *fails to list at all* is caught by the critic's raw-spec survey (the only path that can catch an un-enumerated decision); (c) a **negative example** in which Question 1 correctly declines to escalate a decision that looks weighty but isn't. All four Question-2 tells appear with a worked example in the vocabulary. Note 5(b) exercises the survey on one *planted* decision — it demonstrates the path exists and fires, not its recall on decisions nobody thought to plant; that recall is the open hypothesis the cross-vendor trigger (Out of scope) exists to revisit.
6. A **drift test** asserts the marker-delimited canonical two-questions block matches across `architect.md`, `reviewer.md`, and `orchestrator.md` after trailing-whitespace normalization; it fails on substantive divergence but not on cosmetic whitespace.

## Files touched

- `agents/architect.md` — two-question reflex, sharpened resolve-don't-escalate, full decision inventory, canonical block markers.
- `agents/reviewer.md` — self-contained spec-critique mode (raw-spec survey + flagged audit), arguing verdict, bimodal frontmatter, explicit mode signal, read-only caveat, canonical block markers.
- `agents/orchestrator.md` — inventory audit trigger, total/ordered model rule with degrade-and-warn, per-pass re-review, visible terminal state, critic-failure handling, gate presentation, cost/tier notes, canonical block markers; dated amendment note per house convention.
- Test suite (`tests/`) — drift test for the canonical block; validation scenarios (b) and (c) from Acceptance criteria #5.
- Manifest/build line updates follow from the standard `install.sh` reinstall (both `~/.claude` and `~/.claude-jay`).

## Out of scope (see `PARKING-LOT.md`)

- Cross-vendor critic for genuine lineage independence (the real fix for the independence limitation named above). **Promotion trigger (not merely parked):** build it when either (i) a post-ship incident shows the same-lineage critic missed a stopped-short or un-enumerated consequential decision, or (ii) the raw-spec survey's recall proves insufficient in practice — see `PARKING-LOT.md`.
- Team-wide decision discipline across all specialists.
