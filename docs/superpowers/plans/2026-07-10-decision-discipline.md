# Decision Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a decision-quality discipline (two questions + a second-opinion spec critic) to the agent team by editing three agent prompt files, guarded by a drift test and a documented behavioral-validation procedure.

**Architecture:** The "two questions" vocabulary is inlined verbatim into `architect.md`, `reviewer.md`, and `orchestrator.md` as a marker-delimited canonical block (Approach A — no shared runtime dependency); a bash drift test asserts the three copies stay identical. Role-specific instructions wrap that block in each file. No source code changes — the deliverables are agent instructions plus one test and one validation doc.

**Tech Stack:** Markdown agent definitions; bash + `awk`/`sed`/`jq` test scripts under `tests/`, registered in `install.sh --check`.

## Global Constraints

- **Canonical block is byte-identical modulo trailing whitespace** across the three agent files; the drift test enforces this. When editing any agent file, never touch text between `<!-- two-questions:start -->` and `<!-- two-questions:end -->` except to change all three identically.
- **Reserve the word GATE** for human-approval moments only; the two questions are self-checks, never called "gates."
- **No new package installs, no `rm`/`mv`** — the team's policy hooks forbid them; these tasks only edit files in place.
- **Tier-strength order** (used by the orchestrator model rule) is exactly: `haiku < sonnet < opus < fable`.
- Canonical spec: `docs/superpowers/specs/2026-07-10-decision-discipline-design.md`. Every task's requirements implicitly include it.

## Preconditions

- Work happens on branch `decision-discipline` (already created; spec + `PARKING-LOT.md` already committed there as `5c7d3fa`).
- `agents/orchestrator.md` carries an **uncommitted 2026-07-09 picker fix** (3 edits wiring `AskUserQuestion` into Gates). These plan edits build on top of it. **Task 0 commits that picker fix first** so the branch history is coherent before new work layers on.
- The canonical block text is defined once in Task 1 and referenced verbatim by Tasks 2–4. It is reproduced in full in Task 1; later tasks say "the canonical block from Task 1" and must not paraphrase it.

---

## Task 0: Commit the pending picker fix

**Files:**
- Modify (commit only): `agents/orchestrator.md`

- [ ] **Step 1: Confirm the working-tree picker-fix edits are present**

Run: `git diff --stat agents/orchestrator.md`
Expected: shows modifications to `agents/orchestrator.md` (the Gates picker fix + amendment note).

- [ ] **Step 2: Commit only the picker fix**

```bash
git add agents/orchestrator.md
git commit -m "$(cat <<'EOF'
feat(orchestrator): surface genuine gate decisions through the AskUserQuestion picker

Prior behavior folded either/or decisions into a recommendation paragraph
("approve as-is"), burying the choice. Wire the picker into Gates so genuine
decisions are put to the human as a labeled choice.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SFV9nHDLMym2pfW7YC3RYF
EOF
)"
```

- [ ] **Step 3: Verify clean tree for orchestrator.md**

Run: `git status --short agents/orchestrator.md`
Expected: no output (orchestrator.md fully committed; the unrelated untracked plan file may still show).

---

## Task 1: Canonical two-questions block + drift test

Establishes the shared vocabulary in all three files and the test that keeps them in sync. This is the one TDD-shaped task: write the drift test first, watch it fail (no blocks yet), insert identical blocks, watch it pass.

**Files:**
- Create: `tests/test_decision_discipline_drift.sh`
- Modify: `agents/architect.md` (insert block after the opening paragraph, before `**Scale to the tier stated in your dispatch.**`)
- Modify: `agents/reviewer.md` (insert block after the opening paragraph ending `…you never fix.`)
- Modify: `agents/orchestrator.md` (insert block as a new `## Decision discipline` section immediately before `## Gates`)
- Modify: `install.sh` (register the new test alongside the others, ~line 52)

**Interfaces:**
- Produces: the marker-delimited canonical block (identical text in all three agent files) that Tasks 2–4 wrap with role-specific instructions. The exact block text is below and is authoritative.

**The canonical block (verbatim — identical in all three files):**

```markdown
<!-- two-questions:start -->
**Two questions for every decision.** (The word GATE stays reserved for human-approval moments; these are questions you ask yourself, not gates.)

1. **Does this matter?** Most decisions don't — make those well and move on, no litigating. A decision *matters*, and must be genuinely worked, when it sets a contract someone downstream depends on (output shape, data semantics, exit codes), touches correctness / data-integrity / security, is hard to reverse or changes scope, or is one two good engineers would plausibly resolve differently. Everything else — which stdlib module, file layout, naming — you decide well and move past. Trivial never means careless; it means don't hold a hearing over it.

2. **Did I actually work it?** For the decisions that matter, the failure isn't getting it wrong — it's stopping short and dressing it up as done. You've stopped short when you catch yourself: presenting **a binary with a default** ("A or B, recommend A") instead of asking whether a third option dissolves the tradeoff; **meeting a requirement by quietly shrinking it**; **pushing the hard part to a "follow-up"** or "downstream can handle it"; or **writing a label where an argument belongs** ("simpler and predictable," with no reasoning under it). When a decision matters, work it: first try to dissolve the binary; if it's genuinely open, get a second opinion, or sketch a few independent designs and judge them separately, then together. What is *still* a real either/or after that — and only that — goes to the human. To answer a stopped-short finding there are two ways back: **finish** it (the approach was right, just incomplete) or **rework** it (the shortcut was the framing, and it needs a better frame).
<!-- two-questions:end -->
```

- [ ] **Step 1: Write the failing drift test**

Create `tests/test_decision_discipline_drift.sh`:

```bash
#!/usr/bin/env bash
# tests/test_decision_discipline_drift.sh — the canonical two-questions block
# must be identical (modulo trailing whitespace) across the three agent files.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HERE/../agents"
FILES="architect.md reviewer.md orchestrator.md"
PASS=0
FAIL=0

# Extract the marker-delimited block, stripping trailing whitespace per line.
extract() {
  awk '/<!-- two-questions:start -->/{f=1;next} /<!-- two-questions:end -->/{f=0} f' "$1" \
    | sed 's/[[:space:]]*$//'
}

REF=""
REF_FILE=""
for f in $FILES; do
  path="$AGENTS/$f"
  block="$(extract "$path")"
  if [ -z "$block" ]; then
    FAIL=$((FAIL+1)); echo "FAIL: $f has no non-empty two-questions block"; continue
  fi
  if [ -z "$REF" ]; then
    REF="$block"; REF_FILE="$f"; PASS=$((PASS+1)); continue
  fi
  if [ "$block" = "$REF" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $f block differs from $REF_FILE"
    diff <(printf '%s' "$REF") <(printf '%s' "$block") || true
  fi
done

echo "decision-discipline drift tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_decision_discipline_drift.sh`
Expected: FAIL — `architect.md has no non-empty two-questions block` (markers not inserted yet), exit nonzero.

- [ ] **Step 3: Insert the canonical block into `agents/architect.md`**

Insert the canonical block (with a blank line before and after) immediately before the line `**Scale to the tier stated in your dispatch.**`.

- [ ] **Step 4: Insert the canonical block into `agents/reviewer.md`**

Insert the same canonical block immediately after the opening paragraph that ends `You review; you never fix.`

- [ ] **Step 5: Insert the canonical block into `agents/orchestrator.md`**

Insert a new section immediately before `## Gates`:

```markdown
## Decision discipline

<!-- two-questions:start -->
…canonical block verbatim…
<!-- two-questions:end -->

You apply **Question 1** yourself when auditing the architect's decision inventory (see below); the architect and the spec critic apply both questions in their own work.
```

(Use the exact canonical block text from Step 1 in place of the ellipsis.)

- [ ] **Step 6: Run the drift test to verify it passes**

Run: `bash tests/test_decision_discipline_drift.sh`
Expected: PASS — `decision-discipline drift tests: PASS=3 FAIL=0`, exit 0.

- [ ] **Step 7: Register the test in `install.sh`**

After the existing line that runs `tests/test_dispatch_guard.sh` (~line 52), add:

```bash
bash "$REPO/tests/test_decision_discipline_drift.sh" >/dev/null || fail "decision-discipline drift test failed — run tests/test_decision_discipline_drift.sh to see which"
```

- [ ] **Step 8: Verify the block extractor is robust and the suite is green**

Run: `bash -n tests/test_decision_discipline_drift.sh && bash tests/test_decision_discipline_drift.sh`
Expected: exit 0, `PASS=3 FAIL=0`.

- [ ] **Step 9: Commit**

```bash
git add tests/test_decision_discipline_drift.sh install.sh agents/architect.md agents/reviewer.md agents/orchestrator.md
git commit -m "feat: canonical two-questions block in agent files + drift test"
```

---

## Task 2: Architect — inventory, reflex, resolve-don't-escalate

**Files:**
- Modify: `agents/architect.md` (role-specific prose; do NOT touch the canonical block)

**Interfaces:**
- Produces: the full decision-inventory report format the orchestrator's audit (Task 4) consumes — every decision listed, consequential ones with options/chosen/reasoning/status, trivial ones one line each as `not consequential: <why>`.

- [ ] **Step 1: Add the two-question reflex line under the block**

Immediately after the canonical block in `architect.md`, add:

```markdown
Apply these two questions to every design decision you make, regardless of the dispatch's tier — a decision that matters can hide inside a small task. This is cheap: most decisions are one-line "doesn't matter" calls.
```

- [ ] **Step 2: Sharpen the existing resolve-don't-escalate paragraph**

In the paragraph beginning `**Resolve, don't escalate, when you already have the answer.**`, append this sentence before its final sentence:

```markdown
You resolve most decisions precisely because working them dissolves the false binary; you escalate only what is genuinely still an either/or after that — never a binary you have not first tried to dissolve. (Worked example: "strings vs. inferred types" is not a real binary — strings-by-default plus an opt-in `--infer-types` flag dissolves it.)
```

- [ ] **Step 3: Replace the report-format sentence with the full-inventory requirement**

Find the sentence in the final report paragraph beginning `Your final message is a report to the orchestrator: artifact paths, key decisions made…`. Replace the "key decisions made … open questions" clause with:

```markdown
Your final message is a report to the orchestrator. It MUST include a **full decision inventory** — every decision you made, not only the ones you judged important:
- *Consequential* decisions (Question 1 = matters): the decision, the options considered, the chosen one **and the reasoning under it**, and whether it is resolved or a genuine either/or for the human.
- *Trivial* decisions: one line each — the decision and `not consequential: <why>`.
This inventory makes your triage itself auditable; a "list only what matters" report structurally cannot be audited for a mis-triaged decision. Also give artifact paths and, separately, the genuine either/or questions the human must settle at the gate (reserve that list for real direction/scope/risk tradeoffs).
```

- [ ] **Step 4: Verify no code/markdown breakage and drift intact**

Run: `bash tests/test_decision_discipline_drift.sh`
Expected: PASS=3 FAIL=0 (canonical block untouched).

- [ ] **Step 5: Commit**

```bash
git add agents/architect.md
git commit -m "feat(architect): two-question reflex + full decision inventory report"
```

---

## Task 3: Reviewer — spec-critique mode

**Files:**
- Modify: `agents/reviewer.md` (frontmatter `description`, and body; do NOT touch the canonical block)

**Interfaces:**
- Consumes: the architect's decision inventory (Task 2) and the raw spec.
- Produces: a per-decision verdict (`worked` / `stopped-short`) with an argued justification, consumed by the orchestrator's routing (Task 4).

- [ ] **Step 1: Update the frontmatter description to reflect the bimodal role**

Replace the `description:` line in the frontmatter with:

```yaml
description: Reviews code changes for quality and security, and critiques specs for decision quality (stopped-short tells). Dispatched by the orchestrator; the dispatch names which mode. Not for direct casual use.
```

- [ ] **Step 2: Add the spec-critique mode section**

After the canonical block in `reviewer.md`, add:

```markdown
## Spec-critique mode

When your dispatch names **spec-critique mode** (it will say so explicitly — do not infer mode from the artifact type), you critique a spec's decisions instead of reviewing a code diff. Do two things:

1. **Survey the raw spec text, section by section**, for consequential decisions the architect did NOT surface as decisions at all — recording, for each section, either the decisions you found or an explicit "no consequential decision here," so your coverage is auditable rather than a vague once-over. This survey is the only check that catches a decision the architect never enumerated; do not trust the inventory to be complete.
2. **Audit each flagged consequential decision** through Question 2's stopped-short tells.

Your verdict per consequential decision is **worked** or **stopped-short**. A "worked" verdict MUST state *why the decision survived scrutiny* — not merely "no tell fired." (A bare "no tell fired → worked" is itself tell #4, a label where an argument belongs.) On rework, when re-dispatched, re-check only the specific findings you raised — confirm the named tells are cleared — not a full re-survey.

**Read-only caveat:** you retain `Bash` from your code-review role, so "never rewrite the spec" is enforced by this instruction, not by your tool surface. Honor it; findings flow back to the architect via the orchestrator, exactly like code findings flow to the builder.
```

- [ ] **Step 3: Verify drift intact**

Run: `bash tests/test_decision_discipline_drift.sh`
Expected: PASS=3 FAIL=0.

- [ ] **Step 4: Commit**

```bash
git add agents/reviewer.md
git commit -m "feat(reviewer): spec-critique mode with raw-spec survey and argued verdict"
```

---

## Task 4: Orchestrator — trigger, model rule, routing, terminal state

**Files:**
- Modify: `agents/orchestrator.md` (add to the `## Decision discipline` section from Task 1; add a dated amendment note; do NOT touch the canonical block)

**Interfaces:**
- Consumes: the architect's full inventory (Task 2) and the critic's verdicts (Task 3).
- Produces: gate presentations (via the already-wired `AskUserQuestion` picker) including load-bearing degraded gates.

- [ ] **Step 1: Add the trigger + routing subsection**

Append to the `## Decision discipline` section (after the line added in Task 1 Step 5):

```markdown
### Auditing the architect and convening the spec critic

1. **Audit the inventory, re-triaging every trivial line.** When the architect returns, read the **full** inventory and apply Question 1 to *every* entry — re-triage each one-line "trivial" call, do not sample (they are one line each). If your read and the architect's disagree on whether a decision matters, **your judgment wins** and you dispatch the critic. Honest framing: the inventory audit and this re-triage can only inspect *enumerated* decisions — the only catch for a decision never surfaced as one is the critic's raw-spec survey. So detection is one omission-catch plus two enumeration-dependent audits, not three interchangeable paths.
2. **If any consequential decision is present, dispatch the spec critic before the gate.** Dispatch the reviewer in **spec-critique mode** (name the mode explicitly) on a **different model than the architect ran, one tier stronger** (`haiku < sonnet < opus < fable`); if the architect ran `fable`, run the critic one tier weaker (`opus`). If no distinct model is available, dispatch the same model and flag the gate `independence: degraded — critic ran the architect's model`. This flag fires ONLY on the degraded path — a clean differently-tiered pass carries no independence banner (a caveat recited every gate trains the human to ignore it).
3. **Route findings; re-check per pass; define the end.** "Stopped-short" findings loop back to the architect (its call: finish or rework); after each pass the critic re-checks only its own findings. Bound this by its own max-two-loop counter — a separate instance of the rule, NOT the shared build-phase repair counter. **Terminal state (load-bearing, not a banner):** if the critic still returns stopped-short after two passes, do not proceed silently and do not merely annotate — take the outstanding findings to the human **as the gate's decision content, through the `AskUserQuestion` picker** ("here are the N still-contested points; choose"). Fail-visible, never fail-open.
4. **Critic non-completion — one retry, then a load-bearing flag.** If the critic dispatch errors or times out, retry it **once**. If it still does not complete or is skipped, present the decisions **as unreviewed** through the picker, flagged `critic did not complete` — never as checked when the check did not run.
5. **Cost/tier:** the critic and any rework are added spend on *consequential* specs only, visible per-dispatch in the closeout report. Trivial-tier tasks and Small tasks with no consequential decision fire no critic and pay only the one-line-per-decision inventory cost.
```

- [ ] **Step 2: Add the dated amendment note**

At the end of the file, after the last existing `**Amendment 2026-07-09 …**` note, add:

```markdown
**Amendment 2026-07-10 — decision discipline.** A live session showed the architect handing up false binaries as approve-as-is defaults, undetected until the human intervened twice. Added: the two-questions block (shared, drift-tested), the architect's full decision inventory, an audit-the-inventory trigger, a second-opinion spec critic (reviewer reused on a different model tier, with honest partial-independence framing and degrade-and-warn), targeted per-pass re-review, a load-bearing terminal state routed through the picker, and critic-non-completion handling. See `docs/superpowers/specs/2026-07-10-decision-discipline-design.md`.
```

- [ ] **Step 3: Verify drift intact and the suite green**

Run: `bash tests/test_decision_discipline_drift.sh`
Expected: PASS=3 FAIL=0.

- [ ] **Step 4: Commit**

```bash
git add agents/orchestrator.md
git commit -m "feat(orchestrator): audit inventory, convene spec critic, load-bearing degraded gates"
```

---

## Task 5: Behavioral validation procedure (manual)

AC#5 requires behavioral validation that a unit test cannot provide — it needs real orchestrator/architect/critic dispatches. This task documents a repeatable manual procedure rather than pretending it is automated.

**Files:**
- Create: `docs/superpowers/validation/2026-07-10-decision-discipline-validation.md`

- [ ] **Step 1: Write the validation procedure**

Create the file with three scenarios and their expected outcomes:

```markdown
# Decision-discipline validation (manual)

Run these against the installed team (`claude --agent orchestrator`) after `bash install.sh`. Each records expected behavior; a human confirms.

## (a) Origin replay — stopped-short binary is caught pre-human
Task: "Build a CSV→JSON CLI in a fresh temp project; full pipeline, skip deploy."
Expect: the architect inventories the value-typing decision as consequential; if it hands up a strings-vs-typed binary, the spec critic flags it `stopped-short` (tell: binary-with-default) and it is worked into the opt-in `--infer-types` design BEFORE the human gate. Only a genuine residual either/or (if any) reaches the picker.

## (b) Un-enumerated decision — caught by the raw-spec survey
Task: a different-shape task whose spec omits a consequential decision the architect fails to list at all (e.g., a log-parser spec silent on how to handle timezone-naive timestamps — a data-semantics contract).
Expect: the inventory audit cannot catch it (not enumerated); the critic's section-by-section raw-spec survey flags the missing decision. NOTE: this exercises the survey on one *planted* omission — it demonstrates the path fires, not its recall on omissions nobody planted. Recall is the open hypothesis behind the cross-vendor promotion trigger.

## (c) Negative example — Question 1 correctly declines
Task: any spec whose only open choice is internal and reversible (e.g., which stdlib module parses the input, identical output either way).
Expect: the architect lists it `not consequential: <why>`, the orchestrator's re-triage agrees, no critic fires, no human gate for it. Confirms "does this matter?" can say NO — the over-process guard.

## Tell coverage
Confirm the canonical block names all four tells with a worked example: binary-with-default (`--infer-types`), shrinking a requirement, offloading to a follow-up, label-where-an-argument-belongs.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/validation/2026-07-10-decision-discipline-validation.md
git commit -m "docs: manual behavioral-validation procedure for decision discipline"
```

---

## Self-Review

**Spec coverage:** architect inventory/reflex/resolve (Task 2) ✓; reviewer spec-critique mode + argued verdict + read-only caveat (Task 3) ✓; orchestrator trigger/model-rule/routing/terminal-state/critic-failure/cost (Task 4) ✓; canonical block + drift test (Task 1) ✓; validation scenarios a/b/c + tell coverage (Task 5) ✓; honest independence framing lives in the spec and the degraded-only flag (Task 4) ✓. Picker gate presentation is the already-committed Task 0 fix, reused by Task 4 ✓.

**Placeholder scan:** the only ellipsis is in Task 1 Step 5, explicitly instructed to be replaced with the verbatim block from Step 1 — not a placeholder in the deliverable. No TBD/TODO.

**Type consistency:** the canonical block text is defined once (Task 1) and referenced, never paraphrased. Verdict values (`worked`/`stopped-short`) and gate flags (`independence: degraded`, `critic did not complete`) match between Tasks 3 and 4. Tier order string is identical in Global Constraints and Task 4.
