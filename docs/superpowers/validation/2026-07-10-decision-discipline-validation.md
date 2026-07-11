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
