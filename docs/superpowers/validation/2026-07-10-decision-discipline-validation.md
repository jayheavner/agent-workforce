# Decision-discipline validation (manual)

These validate behavior a unit test can't — they need real orchestrator/architect/critic dispatches. Run against the installed team (`claude --agent orchestrator`) after `bash install.sh`. Each records expected behavior; a human confirms.

## (a) Origin replay — stopped-short binary is caught pre-human
Task: "Build a CSV→JSON CLI in a fresh temp project; full pipeline, skip deploy."
Expect: the architect inventories the value-typing decision as consequential; if it hands up a strings-vs-typed binary, the spec critic flags it `stopped-short` (tell: binary-with-default) and it is worked into the opt-in `--infer-types` design BEFORE the human gate. Only a genuine residual either/or (if any) reaches the picker.

## (b) Un-enumerated decision — caught by the raw-spec survey
Task: a different-shape task whose spec omits a consequential decision the architect fails to list at all — e.g. a log-parser spec silent on how to handle timezone-naive timestamps (a data-semantics contract).
Expect: the inventory audit cannot catch it (not enumerated); the critic's section-by-section raw-spec survey flags the missing decision. NOTE: this exercises the survey on one *planted* omission — it demonstrates the path fires, not its recall on omissions nobody planted. Recall is the open hypothesis behind the cross-vendor promotion trigger (`PARKING-LOT.md`).

## (c) Negative example — Question 1 correctly declines
Task: any spec whose only open choice is internal and reversible — e.g. which stdlib module parses the input, identical output either way.
Expect: the architect lists it `not consequential: <why>`, the orchestrator's re-triage agrees, no critic fires, no human gate for it. Confirms "does this matter?" can say NO — the over-process guard.

## Tell coverage
Confirm the canonical two-questions block names all four stopped-short tells with a worked example: binary-with-default (`--infer-types`), meeting a requirement by quietly shrinking it, pushing the hard part to a follow-up, and a label where an argument belongs.

---

# Validation runs — executed 2026-07-13 (build 9df4727, live against ~/.claude-jay)

Every branch was exercised, either organically (a real orchestrator run dispatching real agents) or by a directed drill (orchestrator-level reasoning about a stipulated state, since failure branches can't be forced organically). Zero logic-only gaps remain.

### Run 1 — organic, design phase (omission-catch)
Task: CSV→JSON CLI, small tier. Result: architect emitted a full inventory (6 consequential + ~12 trivial one-liners); orchestrator re-triaged every trivial line and pre-flagged two borderline contracts; spec critic ran on **fable** (architect on **opus** — distinct, clean independence, no degraded banner, completed first try); verdict REQUEST-CHANGES with five argued stopped-short findings. **Key proof:** the raw-spec survey caught two contract violations (argparse exit-2 breaking the "all exits 0/1" contract; missing exception catches) that the architect never enumerated — the omission-catch no inventory audit could make — and flagged `_extra` as mis-tiered (trivial→consequential). Gate logic correct: all findings resolved by the spec's own philosophy → no residual either/or → no picker.

### Run 2 — organic, full rework loop
Task: CSV→JSON CLI (validate2), small tier. Result: **rework loop fired** — critic returned 4 stopped-short findings → architect FINISHed 3 / REWORKed 1 → **critic re-checked ONLY its own 4 findings** (confirmed verbatim: "I did not re-survey other sections; no new findings raised"), all cleared in **one** pass → reached GATE 1 cleanly. This run surfaced two **genuine residual either/ors** (formatting default; in-memory vs streaming), presented as picker questions with recommended options. Clean independence (fable vs opus, no banner). **Incidental:** the critic hit a policy hook mid-run and fell back gracefully — live confirmation the hook-path fix works (policy hook fired from the pinned `~/.claude/hooks` during a `~/.claude-jay` session).

### Drill 1 — directed, terminal state
Stipulated: F1 still stopped-short after both rework passes (cap hit). Result: orchestrator **held GATE 1 (not passed)**, attached flag `decision unresolved after 2 rework passes — F1 still stopped-short; human decision required`, put F1 into the picker **as the gate's decision content** (options A/B/C, recommended labeled), and explicitly refused to proceed to build, re-loop a third pass, or present the spec as clean. Fail-visible, never fail-open — as designed.

### Drill 2 — directed, degrade-and-warn + critic non-completion
Degrade (no distinct model): critic still convened on the architect's own model, gate flagged `independence: degraded — critic ran the architect's model`, **not** presented as independently-checked; confirmed the banner fires only on the degraded path, never on a clean run. Non-completion (dispatch timeout): **retry once**, then if still failing, decisions surfaced through the picker flagged `critic did not complete`, characterized as **unreviewed**, never as checked. Both as designed.

**Summary:** full inventory · audit + mis-tier catch · spec-critique dispatch · model rule (opus→fable, distinct) · raw-spec omission-catch · argued verdicts · rework loop with own-findings-only re-review · picker for genuine residuals · clean-independence · terminal-state fail-visible · degrade-and-warn · critic-retry — all exercised, none misfired. Hook-path fix confirmed live.
