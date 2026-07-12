# Gap Detection & Capability Improvement Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the gap-detection loop specified in
`docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md`: a domain
sensor in the architect, gap handling + a session-start clause in the orchestrator, the
gap-record schema, and the shakedown scenarios.

**Architecture:** Pure instruction-text and documentation change — two agent markdown
files gain normative blocks, one new schema README is created, the repo README's
shakedown checklist gains five scenarios. A presence test (grep-based, in the style of
the existing drift test) locks the load-bearing phrases in place.

**Tech Stack:** Markdown agent definitions, POSIX bash tests (repo convention:
standalone scripts with PASS/FAIL counters, exit 0 only when FAIL=0).

## Global Constraints

- Only `agents/architect.md` and `agents/orchestrator.md` change among installed files —
  no other agent file, no hooks, no `install.sh` changes (spec §7).
- No new agents, routes, or drift-test blocks (spec §2, §6, non-goals).
- Normative text must match the spec **verbatim** where quoted below — the spec's exact
  wording was panel-reviewed twice; do not paraphrase.
- Total new instruction text stays ≈32 lines across the two agent files (spec §7).
- The repo forbids nothing this plan needs (no package installs, no file deletes).
- After the final task, the edited agent files are NOT live until a human runs
  `bash install.sh` — the plan ends with `--check` showing expected DRIFT, never with
  running the installer.

---

### Task 1: Gap-record schema and the presence test harness

**Files:**
- Create: `tests/test_gap_loop_text.sh`
- Create: `docs/gaps/README.md`

**Interfaces:**
- Produces: `expect_grep <repo-relative-file> <fixed-string> <label>` helper in
  `tests/test_gap_loop_text.sh` — Tasks 2 and 3 append `expect_grep` lines to this file.
- Produces: `docs/gaps/README.md` — the schema the orchestrator's Gap flags text
  (Task 3) tells the scribe to read.

- [ ] **Step 1: Write the failing test**

Create `tests/test_gap_loop_text.sh`:

```bash
#!/usr/bin/env bash
# tests/test_gap_loop_text.sh — verifies the gap-loop normative text landed in the
# agent files and the gap-record schema exists. Presence checks, not drift checks:
# these phrases are load-bearing (sensors, schema fields, disclosure lines) and a
# future edit that drops one silently disables part of the loop.
# Spec: docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
PASS=0
FAIL=0

expect_grep() { # $1 repo-relative file, $2 fixed string, $3 label
  if [ -f "$ROOT/$1" ] && grep -qF -- "$2" "$ROOT/$1"; then
    PASS=$((PASS+1)); echo "PASS: $3"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $3 — not found in $1: $2"
  fi
}

# --- Task 1: gap-record schema ---
expect_grep docs/gaps/README.md "schema: 1" \
  "gap README declares schema v1"
expect_grep docs/gaps/README.md "kind: domain | fit | permission/tool | process" \
  "gap README lists the four gap kinds"
expect_grep docs/gaps/README.md "does not exist for promotion purposes" \
  "gap README carries the canonical-main rule"
expect_grep docs/gaps/README.md "Declined is not terminal" \
  "gap README carries decline semantics"
expect_grep docs/gaps/README.md "GAP-<YYYYMMDD>-<kind>-<slug>.md" \
  "gap README defines the record filename"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_gap_loop_text.sh`
Expected: 5 FAIL lines (docs/gaps/README.md does not exist), `passed=0 failed=5`, exit 1.

- [ ] **Step 3: Create the schema README**

Create `docs/gaps/README.md`:

````markdown
# Gap records

One file per detected capability gap, written by the scribe on the orchestrator's
dispatch. Filename: `GAP-<YYYYMMDD>-<kind>-<slug>.md`. The orchestrator assigns
`<kind>-<slug>` in the dispatch — slug at field granularity (`payroll`, never
`payroll-withholding`); coarse slugs over-link, which is the safe direction for the
promotion trigger. Same `<kind>-<slug>` = same gap.

Spec: `docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md`.

## Schema (v1)

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

## Rules for the scribe

- List this directory before writing; link every earlier record with the same
  `<kind>-<slug>` on the `recurrence:` line.
- Never edit or delete an existing record. Records are evidence.

## Semantics

- **Evidence, not workflow.** A record freezes once its status leaves `open`:
  `promoted` points at the spec or ticket where the work is tracked; `declined` keeps
  the reason. This directory never becomes a second ticket system.
- **Declined is not terminal — the reason carries forward.** A new detection with a
  previously-declined identity is still logged, links the declined record in
  `recurrence:`, and is presented at the gate with the decline attached
  (`— note: declined <date>, reason: <reason>`). It re-opens the question only when
  the human says the stated reason no longer holds.
- **Canonical main or it doesn't count.** Promotion decisions happen only against this
  repository's main. A record not in canonical main does not exist for promotion
  purposes; local and degraded-path records count for nothing until merged. Default
  promotion trigger: a second record with the same `<kind>-<slug>`, or the human
  explicitly asking — promotion is always the human's decision.
- **Relation to `PARKING-LOT.md`:** the parking lot holds human-curated deferred
  *ideas*; this directory holds machine-written observed *evidence*. An idea may cite
  gap records as its promotion trigger.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_gap_loop_text.sh`
Expected: 5 PASS lines, `passed=5 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/test_gap_loop_text.sh docs/gaps/README.md
git commit -m "feat(gaps): gap-record schema v1 and presence test harness"
```

---

### Task 2: Architect domain sensor

**Files:**
- Modify: `agents/architect.md` (insert one paragraph immediately AFTER the paragraph
  beginning `**Investigate before you design.**`, currently line 41)
- Modify: `tests/test_gap_loop_text.sh` (append assertions)

**Interfaces:**
- Consumes: `expect_grep` from Task 1.
- Produces: the `DOMAIN GAP: <field>` report token and `domain-uncertified` criterion
  label that Task 3's orchestrator text reacts to.

- [ ] **Step 1: Append failing assertions to the test**

Append to `tests/test_gap_loop_text.sh`, directly above the `echo "passed=..."` line:

```bash
# --- Task 2: architect domain sensor ---
expect_grep agents/architect.md "practitioner test" \
  "architect carries the practitioner test"
expect_grep agents/architect.md "DOMAIN GAP: <field>" \
  "architect declares DOMAIN GAP in reports"
expect_grep agents/architect.md "the plan is the carrier" \
  "architect states plan-as-carrier"
expect_grep agents/architect.md "domain-uncertified" \
  "architect labels uncertified criteria"
expect_grep agents/architect.md "stop-and-report to the orchestrator, never the builder" \
  "architect plans forbid builder domain improvisation"
```

- [ ] **Step 2: Run test to verify the new assertions fail**

Run: `bash tests/test_gap_loop_text.sh`
Expected: `passed=5 failed=5`, exit 1 (Task 1 assertions still pass).

- [ ] **Step 3: Insert the domain-sensor paragraph**

In `agents/architect.md`, immediately after the `**Investigate before you design.**`
paragraph, insert this paragraph (verbatim — spec §1):

```markdown
**The practitioner test — domain gaps.** As part of investigation, apply the practitioner test: would a practitioner of some field reject output that merely satisfies this spec? If yes, correctness here is judged by that field's norms, not by the spec alone — true of accounting, tax, payroll, legal, medical, and insurance work, and equally of unlicensed fields with hard norms (logistics, actuarial pricing, manufacturing tolerances). When the test fires, Glob the installed skills for a `domain-<field>` skill. If one exists, invoke it and carry its constraints into the spec and plan explicitly — the builder cannot load skills, so **the plan is the carrier** of domain constraints, and every domain-constrained plan must state: domain questions this plan does not answer are stop-and-report to the orchestrator, never the builder's own judgment call. If no skill exists, declare `DOMAIN GAP: <field>` in your report, name the norms you believe are load-bearing (even approximately — "there are matching and cutoff conventions I don't know"), and do not write the spec until the orchestrator supplies researcher-gathered domain input. Label every acceptance criterion that rests on that input `domain-uncertified`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_gap_loop_text.sh`
Expected: `passed=10 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add agents/architect.md tests/test_gap_loop_text.sh
git commit -m "feat(architect): practitioner-test domain sensor with DOMAIN GAP declarations"
```

---

### Task 3: Orchestrator gap handling, session-start clause, amendment note

**Files:**
- Modify: `agents/orchestrator.md` (three insertions, anchors below)
- Modify: `tests/test_gap_loop_text.sh` (append assertions)

**Interfaces:**
- Consumes: `DOMAIN GAP` token (Task 2), `docs/gaps/README.md` schema path (Task 1).
- Produces: the `gaps:` gate-line convention and the Gap flags procedure — terminal
  deliverable, nothing downstream.

- [ ] **Step 1: Append failing assertions to the test**

Append to `tests/test_gap_loop_text.sh`, directly above the `echo "passed=..."` line:

```bash
# --- Task 3: orchestrator gap handling ---
expect_grep agents/orchestrator.md "## Gap flags" \
  "orchestrator has the Gap flags section"
expect_grep agents/orchestrator.md "hard is never a gap" \
  "orchestrator carries the discriminator"
expect_grep agents/orchestrator.md '`gaps: none`' \
  "orchestrator requires the gate gaps line"
expect_grep agents/orchestrator.md "await upstreaming" \
  "orchestrator session-start reports stray records"
expect_grep agents/orchestrator.md "Amendment 2026-07-12 — gap detection" \
  "orchestrator amendment note recorded"
```

- [ ] **Step 2: Run test to verify the new assertions fail**

Run: `bash tests/test_gap_loop_text.sh`
Expected: `passed=10 failed=5`, exit 1.

- [ ] **Step 3: Make the three insertions**

**(a) Session-start clause.** In the `## Triage first` section, the paragraph beginning
`At the start of every session, Read $HOME/.claude/agent-team-manifest.json` currently
ends with `never skip it.` Append to that same paragraph:

```markdown
After the build line, Glob the current project's `docs/gaps/` and, if any `GAP-*.md` records exist there, add one line: "N gap records in this project await upstreaming" — degraded-path strays stay visible every session until a human moves them, and records count toward promotion only once they are in the canonical repo's main.
```

**(b) Gap flags section.** Insert a new section immediately after the `## Routes`
section (i.e. between the `Research / ops / documents / tickets:` paragraph and
`## Factual questions are dispatches, not memory`), verbatim from spec §3:

```markdown
## Gap flags

Two signals name a capability gap: an architect `DOMAIN GAP`, or your own gate-time review of task friction (repeated policy blocks, work no specialist fits, a route that fights the task's shape). Apply investigate-first before accepting either: *misfit means the wrong kind of work; hard means the right kind, difficult — hard is never a gap.* On a confirmed gap, never stall and never build capability mid-task:

1. **Fallback.** For a domain gap, dispatch the researcher (sonnet; opus for regulated or high-stakes domains) to gather sourced domain knowledge for this task, labeled *uncertified*, and attach it to the architect/builder dispatch context. For fit friction, re-route to the closest specialist and make the reviewer pass mandatory regardless of tier.
2. **Record.** Assign the record's identity yourself — `<kind>-<slug>`, slug at field granularity (`payroll`, never `payroll-withholding`) — then dispatch the scribe on `haiku`: read `<repo>/docs/gaps/README.md` (repo path from the manifest) and write one gap record per its schema under the identity you assigned. If the manifest is missing or unreadable, have the scribe write a best-effort record — kind, task, gap, fallback — to the current project's `docs/gaps/` instead, and disclose the degraded path at the gate.
3. **Disclose.** Every gate summary carries a mandatory line: `gaps: none` or `gaps: <record filenames>` (a record with a declined history carries its decline reason on the line). A task that proceeded on uncertified domain input says so at each gate, and its gate summary recommends human or domain-expert review of the acceptance criteria themselves.

In the closeout report, gap-handling dispatches (researcher backfill, added reviewer passes, scribe gap records) appear as their own labeled rows.
```

**(c) Amendment note.** Append at the end of the file, after the
`**Amendment 2026-07-10 — decision discipline.**` paragraph:

```markdown
**Amendment 2026-07-12 — gap detection and capability loop.** The team had no way to notice missing domain expertise: a reconciliation-style task would be specced, built, and verified by agents none of whom know the field's norms, with nothing flagging the blindness. Changes: the architect gained the practitioner test (declare `DOMAIN GAP`, plan-as-carrier, `domain-uncertified` labels), this file gained the Gap flags section (fallback, record, disclose — with the hard-is-never-a-gap discriminator) and the session-start stray-record clause. Gap records live in `docs/gaps/` per its schema README; promotion is human-only, evidence-triggered. See `docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_gap_loop_text.sh`
Expected: `passed=15 failed=0`, exit 0.

- [ ] **Step 5: Run the existing drift test to confirm no regression**

Run: `bash tests/test_decision_discipline_drift.sh`
Expected: exit 0 (the two-questions blocks were not touched).

- [ ] **Step 6: Commit**

```bash
git add agents/orchestrator.md tests/test_gap_loop_text.sh
git commit -m "feat(orchestrator): gap flags section, session-start stray-record clause, amendment note"
```

---

### Task 4: Shakedown scenarios and closeout

**Files:**
- Modify: `README.md` (append to the `## Shakedown checklist` section)

**Interfaces:**
- Consumes: everything above; documentation-only task.

- [ ] **Step 1: Append the gap-loop shakedown subsection**

In `README.md`, at the end of the `## Shakedown checklist` section (after the final
`- [ ] 8. …use the team on real work.` item), append:

```markdown
### Gap-loop shakedown

Run after installing the gap-detection amendment (spec:
`docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md`). Scenarios
are ranked, not equal: **scenario 3 is load-bearing** — it tests the
hard-is-never-a-gap discriminator and should re-run after any change to the
orchestrator's Gap flags text. Scenarios 1–2 matter at first domain contact; 4–5 are
documentation-grade.

- [ ] 1. **Domain-positive:** give the team a payroll-withholding-calculator task. Expect
      the architect to declare `DOMAIN GAP: payroll` before writing a spec; researcher
      backfill runs; each gate discloses uncertified input and recommends criteria
      review; a `GAP-*-domain-payroll.md` record appears.
- [ ] 2. **Domain-negative:** the same task with a `domain-payroll` skill installed.
      Expect no gap declared and the skill's constraints visible in the plan.
- [ ] 3. **Hard-but-in-charter negative:** a genuinely difficult refactor entirely inside
      the team's competence. Objective pass condition: every gate summary line reads
      exactly `gaps: none` and no `GAP-*.md` file exists anywhere after the run.
- [ ] 4. **Declined promotion:** decline a recorded gap. Expect the record frozen as
      `declined — <reason>`, and a later same-identity detection presented at the gate
      with that reason attached.
- [ ] 5. **Degraded logging path:** with the manifest absent, expect the record in the
      project's own `docs/gaps/` and the gate disclosing the degraded path; at the next
      session start, expect "1 gap records in this project await upstreaming."
```

- [ ] **Step 2: Verify the addition**

Run: `grep -c "Gap-loop shakedown" README.md`
Expected: `1`

- [ ] **Step 3: Run the full test suite**

Run: `for t in tests/test_*.sh; do echo "== $t"; bash "$t" >/dev/null 2>&1 && echo OK || echo FAILED; done`
Expected: `OK` for every test. (`test_install_skills.sh` and `test_policy_hooks.sh`
exercise hooks/installer paths this plan never touched; a FAILED there is
pre-existing — check `git stash && bash <test>` to confirm before blaming this change.)

- [ ] **Step 4: Confirm install drift is the expected two files**

Run: `bash install.sh --check`
Expected: DRIFT reported for `agents/architect.md` and `agents/orchestrator.md` only.
Do NOT run `bash install.sh` — going live is the human's call.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: gap-loop shakedown scenarios in README checklist"
```
