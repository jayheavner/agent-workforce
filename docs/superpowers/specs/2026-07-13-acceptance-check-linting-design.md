# Acceptance-Check Linting — Design

**Date:** 2026-07-13
**Status:** Draft for human review
**Prior art:** `2026-07-07-ai-agent-team-design.md` (roster, route, gates — unchanged),
`2026-07-10-decision-discipline-design.md` (two-questions vocabulary, the *mechanical
drift-test + human critic* split this design reuses, the reviewer's bimodal
spec-critique role, and the "a warning that costs nothing to bypass is indistinguishable
from no warning → load-bearing, not a banner" principle), `2026-07-12-gap-detection-
capability-loop-design.md` (the `domain-uncertified` criterion label this design must not
let a green check paper over, the *plan is the carrier* rule, and the pattern of shipping
a tool/schema as **repo content referenced by manifest path** rather than an installed
artifact). External prior art: Nate Jones' `ringer` swarm orchestrator, whose
`lint_manifest` (checks that cannot fail, checks that fail silently, underspecified specs,
write collisions) is the mechanism Jay approved porting.

## Goal

Close the weakest link in this team's verify chain: today nothing checks whether a plan's
acceptance criterion *can actually fail*. The architect writes criteria, the verifier
runs them, the reviewer reviews — but a criterion that is tautological ("prints a value,
exit 0"), silently-failing (`grep -q` with no reason on failure), or unfalsifiable
("works correctly") sails through verification while proving nothing. Port ringer's
anti-tautology discipline, adapted to this team: give every acceptance criterion a
declared, falsifiable shape, and lint that shape — deterministically for the mechanical
failure modes, by reviewer judgment for the rest — before the plan clears its gate.

No new agents. No new route. Footprint: instruction text in two agent files (architect,
reviewer) plus one orchestrator line, one stdlib lint tool as repo content, and one bash
test.

## Motivating scenario

An architect writes a Standard-tier plan. One task's acceptance criterion reads:
"Task 4 — config loader handles missing keys gracefully. Verify: `grep -q DEFAULT
config.py`." The verifier runs it: `grep -q` exits 0, criterion "passes," green row in the
report. But `grep -q` prints nothing, so its evidence column is empty; it proves the
string `DEFAULT` appears *somewhere* in the file, not that a missing key is handled, and
if it had failed it would have told no one *why* — starving both the verifier's evidence
trail and the builder's repair loop. A second criterion reads "the error messages are
clear" with no named judge and no statement of what unclear would look like: nothing can
ever answer "no." Both criteria are verification theater. Nothing in the current team
notices, because the failure is in the *criterion*, and every downstream agent trusts the
criterion. The human is the only backstop — and the human is reading a green report.

The insight that shapes this design: **recognizing that a criterion cannot fail does not
require knowing whether the code is correct.** "This check exits 0 no matter what the code
does" and "no reader could ever say this criterion is unmet" are both detectable without
the domain, the code, or the intent — the first by a small deterministic tool, the second
by a competent reviewer's eyes. That detectability is exactly what ringer exploits.

## Non-goals

- **No new agent, no new route, no new gate.** The lint runs inside the *existing*
  plan gate, invoked by the reviewer — the agent already used at that gate as the
  decision-quality critic. Nothing new is dispatched.
- **No installed artifact.** The lint tool is repo content referenced by manifest path,
  exactly like `docs/gaps/README.md` — it is not copied into `~/.claude`, so `install.sh`
  is untouched.
- **No package installs.** The tool is Python 3 standard library only (`re`, `shlex`),
  honoring the permanent no-install constraint.
- **Not a code linter and not a re-verification.** This lints *acceptance criteria* (can
  this criterion fail?), not code and not the code-review surface. It never runs the
  criteria against code — that stays the verifier's job.
- **No format change beyond acceptance criteria.** Plan prose, task structure, and the
  writing-plans checkbox discipline are unchanged; only the acceptance-criterion lines
  gain a declared shape.

## Design overview

Three moves, mirroring how this team already layers a cheap author self-check under a
deterministic mechanical test under a human judge (the decision-discipline pattern):

1. **A declared criterion shape (architect, authoring time).** Every acceptance criterion
   is tagged `(mechanical)` or `(judgment)`. A mechanical criterion carries an executable
   `Check:` (a command plus the observable output that proves it). A judgment criterion
   names its `Judge:` (reviewer or human) and its `Bar:` (what a "no" looks like). This is
   the unifying reframe of the whole design: the property ringer really enforces is not
   "executable" but **falsifiable** — a mechanical criterion is falsifiable by a command,
   a judgment criterion by a named judge against a stated bar. Both must be falsifiable;
   they differ only in *which instrument* can return "no."
2. **A deterministic lint tool (reviewer, at the plan gate).** `tools/
   lint_acceptance_checks.py` parses the tagged criteria and flags the mechanical failure
   modes ringer catches — checks that cannot fail, checks that fail silently, mechanical
   criteria with no check at all. These are deterministic and load-bearing.
3. **Reviewer judgment for the semantic classes.** The tool cannot tell whether a check
   *actually tests its criterion*, whether a judgment bar is meaningful, or whether a
   criterion is mislabeled to dodge the executable requirement. The reviewer's eyes cover
   those, in the same plan-critique pass — the human-judge layer over the mechanical tool,
   precisely the split the decision-discipline design already uses (marker drift-test +
   arguing critic).

Every finding — deterministic or judgment — carries the same three parts ringer's nudges
carry: the class, **why it is a problem**, and **what a good criterion looks like**
(a concrete rewrite). Blocking is never terse.

## 1. The declared criterion shape (architect)

Add to the architect's plan discipline (normative text, ~14 lines). Each acceptance
criterion is one of two shapes:

```
- [ ] AC-N (mechanical): <claim>. Check: `<command>` → expects <observable output>.
- [ ] AC-N (judgment): <claim>. Judge: <reviewer | human>. Bar: <what a "no" looks like>.
```

- A **mechanical** criterion is one a command can decide. Its `Check:` names the exact
  command and the observable that proves the claim — not "exit 0," but *what the command
  prints that a reader can see is the claimed behavior*. This is the same thing the
  `task-verification` skill already demands ("Task MUST have a Verification section with
  specific steps") and it hands the verifier its command and expected output directly, so
  the shape strengthens an existing contract rather than adding a parallel one.
- A **judgment** criterion is one no command can honestly decide — "the spec reads
  clearly," "the API is ergonomic," "the design is sound." It is labeled judgment, never
  dressed as mechanical, and it must name *who* judges and *what a "no" looks like*. A
  judgment criterion with no bar is a judgment-side tautology: unfalsifiable by anyone.
- **The taxonomy is honest, not a loophole.** Labeling a mechanically-checkable claim
  "judgment" to escape writing a `Check:` is itself a lint finding (§3, A3). The tag
  declares which instrument falsifies the claim; it never declares that the claim is
  exempt from falsification.
- **`domain-uncertified` criteria (gap-detection spec §1) keep their label.** A check may
  prove the code *does* X; it can never prove X is the domain-correct behavior. A
  domain-uncertified criterion may carry a mechanical `Check:` for its narrow mechanical
  claim, but the check's `expects` must describe only the mechanical observable, and the
  `domain-uncertified` label stays. A green check must never read as domain certification.

The architect self-lints while authoring — the cheapest catch, applied like the
two-questions reflex (a discipline, not a tool run; the architect has no Bash). The tool
and the reviewer are the enforced backstops, not the primary line.

## 2. Where the lint runs, and who runs it

The lint fires **at the plan gate, before the builder builds** — catching theater before
a whole build is spent on an unfalsifiable target, exactly as ringer lints the manifest
before the run rather than after. Three candidate runners were weighed:

- The **orchestrator** cannot: it has no Bash and no Write, by design.
- The **verifier** has Bash but is dispatched *post-build*; catching a tautological
  criterion there wastes the build. It stays the post-build backstop (its UNCHECKED-with-
  evidence discipline already catches some unfalsifiable criteria late) but is unchanged.
- The **reviewer** has Bash, is read-only, runs *at the gate*, and is already this team's
  gate-time decision-quality critic (spec-critique mode, decision-discipline design). A
  tautological acceptance criterion *is* a stopped-short tell — "meeting a requirement by
  quietly shrinking it" — so this is the same discipline the reviewer already owns, one
  artifact earlier. The reviewer is the runner.

The reviewer gains a **plan-critique mode**, parallel to its existing spec-critique mode:
run `python3 <repo>/tools/lint_acceptance_checks.py <plan-path>` (repo path resolved from
the manifest, the same way the scribe resolves the gap-record schema path), report the
tool's findings, then apply the judgment-class review the tool cannot (§3). Findings flow
to the architect via the orchestrator, exactly as code findings flow to the builder; the
reviewer never rewrites the plan (read-only caveat, enforced by instruction as in the
decision-discipline design — the reviewer retains Bash from its code-review role).

The orchestrator gains **one line**: at the plan gate, dispatch the reviewer in
plan-critique mode. Load-bearing findings become the gate's decision content through the
existing `AskUserQuestion` terminal-state machinery (§3), not a banner.

**The tool is repo content, not an installed artifact.** It lives at `tools/
lint_acceptance_checks.py`, is referenced by manifest repo-path, and rides no `install.sh`
change — the same shape the gap-detection design chose for `docs/gaps/README.md`. Its
correctness is pinned by a bash test in `tests/` (§5).

## 3. Lint classes — what ports, what is new, what is dropped

Ringer's classes were derived for stateless-worker shell manifests; this team's criteria
are markdown authored by a stateful architect for a stateful builder, so the list is
re-derived, not copied.

### Load-bearing (deterministic, tool-detected, block-equivalent)

- **L1 `tautological-check`** — a mechanical criterion whose `Check:` cannot fail:
  `true`, `:`, `exit 0`, or a chain consisting only of `echo`/`printf`. *Direct port of
  ringer `check_cannot_fail`.* Why it is a problem: it passes proving nothing. Good check:
  a command whose output changes with the code under test.
- **L2 `silent-check`** — a `Check:` that may fail without printing why: `grep -q`,
  `diff -q`, or a bare `test -f` / `[ -f … ]` with no failure-output branch (`|| echo …`).
  *Direct port of ringer `check_may_fail_silently`, and the rationale is stronger here:*
  a silent check leaves the verifier's evidence column empty and tells the builder's
  repair loop nothing on failure. Good check: drop `-q`, or add `|| echo "why: <expected
  vs got>"`, so failure prints the reason.
- **L3 `mechanical-criterion-without-check`** — a criterion tagged `(mechanical)` with no
  `Check:` line. *Adapted from ringer's no-`expect_files` finding.* Why: an undeclared
  check is verified by improvisation, and the verifier is handed nothing. Good: add the
  `Check:` command and its expected observable, or re-tag as judgment with a `Bar:`.

### Advisory (heuristic or semantic, explained; tool-flagged or reviewer-eyes)

- **A1 `unfalsifiable-phrasing`** — criterion text leaning on weasel observables ("works
  correctly," "handles X gracefully," "is robust," "as expected") with nothing a reader
  could measure. *Adapts ringer's spec-too-short:* not a character count (our criteria sit
  in rich plan context) but unfalsifiable *phrasing*. The tool flags a known token list as
  advisory; the reviewer confirms.
- **A2 `empty-judgment-criterion`** — a `(judgment)` criterion with no `Judge:` or no
  `Bar:`. A judgment tautology. *New — created by the taxonomy itself.* Good: name the
  judge and state what a "no" looks like ("Judge: reviewer. Bar: an unexplained magic
  number or an un-handled error path is a fail").
- **A3 `mislabeled-criterion`** — a `(judgment)` label on a claim that is plainly
  mechanically checkable (contains observable tokens like "exit code," "returns," "file
  exists," "HTTP 200"), i.e. dodging the `Check:` requirement; or a `(mechanical)` label
  on an inherently subjective claim. *New — the taxonomy's own gaming vector.* Tool flags
  observable-token judgment criteria as advisory; reviewer adjudicates.
- **A4 `uncertified-check-overreach`** — a `domain-uncertified` criterion whose `Check:`
  `expects` clause asserts domain correctness rather than the narrow mechanical observable
  (§1). *New — ties to the gap-detection design.* Reviewer eyes. Good: scope the `expects`
  to the mechanical claim and keep the uncertified label visible.

### Dropped, with rationale

- **Ringer's file-pointer spec** (the brief lives in another file) — already forbidden by
  the writing-plans "No Placeholders" rule ("repeat the code — the engineer may read tasks
  out of order"). Adding it would duplicate an existing discipline.
- **Ringer's write-collision across parallel worktrees** — not applicable. This team
  builds tasks **sequentially** (subagent-driven-development, one task at a time), with no
  parallel worktrees, so two tasks cannot race on a shared path. Re-porting it would flag
  a hazard that the execution model structurally prevents.

## 4. Block vs. warn — posture per class

Ringer's lint is uniformly advisory (it prints and proceeds). This team must be
**split**, for a reason the decision-discipline design already established against its own
flags: *a warning that fires constantly and costs nothing to bypass is indistinguishable
from no warning.* If the tautology and silent-check findings were advisory, the whole port
would be theater about theater.

- **L1, L2, L3 are load-bearing (block-equivalent).** They are deterministic and
  unambiguous — a `grep -q` with no failure branch *is* silent, no judgment call. An
  uncorrected L-class finding does not clear the plan gate silently: it goes back to the
  architect to fix, and if the architect declines or the human wants to proceed anyway,
  the finding becomes the gate's **decision content through `AskUserQuestion`** (the
  load-bearing terminal-state pattern from the decision-discipline design), never a banner
  the human clicks past. Block is on *proceeding*; the explanation is always attached.
- **A1–A4 are advisory, with explanation.** They are heuristic (A1) or semantic judgment
  calls (A2–A4) where a false positive is plausible; the reviewer weighs them and may
  escalate any to request-changes, but they do not auto-block. Every advisory finding
  still carries why-and-what-good-looks-like — advisory never means terse.

The dividing line is *determinism*: if a finding can be wrong, it advises; if it cannot,
it blocks. This is the same line the decision-discipline design draws between its
mechanical drift-test (hard) and its arguing critic (argued, routed).

## 5. The tool, and its test

`tools/lint_acceptance_checks.py` — Python 3 standard library only (`re` for line
parsing, `shlex` for shell-token analysis, ported from ringer's `consists_only_of_echo_
commands`, `is_quiet_grep`, `is_file_existence_test`, `has_failure_output_branch`). It:

1. Parses a plan file's `- [ ] AC-N (mechanical|judgment): …` lines and their `Check:` /
   `Judge:` / `Bar:` clauses.
2. Emits one finding per issue as `CLASS  AC-N  why…  good:…`, load-bearing findings
   prefixed `BLOCK`, advisory prefixed `WARN`, and exits non-zero iff any `BLOCK` finding
   fired (so the reviewer, and the test, get a machine-readable pass/fail plus human-
   readable nudges — ringer's dual output).

**Why Python, not bash** (see decision inventory — this is the top open question). The
load-bearing classes require tokenizing shell commands to distinguish `diff -q … || echo
why` (fine) from `diff -q …` (silent), and `grep -q` from `grep`. Ringer needed `shlex`
for exactly this; a bash/grep reimplementation reintroduces the false-positive risk that
makes a *blocking* lint dangerous. Python 3 is standard on the target dev machines and is
itself the prior art's language. If `python3` is absent, the reviewer degrades to
eyes-only and flags it at the gate — the same honest degrade-and-warn the team uses when a
distinct critic model is unavailable. This introduces a Python toolchain to a previously
bash+jq repo; that maintainability cost is the human's call at review.

`tests/test_acceptance_lint.sh` — bash, repo convention (PASS/FAIL counters, exit 0 iff
FAIL=0), drives the tool over fixture criterion snippets and asserts findings:

- a pure-`echo` check → `BLOCK tautological-check`, exit non-zero;
- `grep -q` / `diff -q` / bare `test -f` with no `|| echo` → `BLOCK silent-check`;
- the same three each with a `|| echo "why…"` branch → **no** finding (guards against
  false positives, the dangerous direction for a blocking lint);
- a `(mechanical)` criterion with no `Check:` → `BLOCK mechanical-criterion-without-check`;
- a `(judgment)` criterion with no `Bar:` → `WARN empty-judgment-criterion`;
- a clean plan with valid mechanical and judgment criteria → zero findings, exit 0.

The tool is not installed, so `install.sh` is unchanged; the test runs in the existing
`for t in tests/test_*.sh` loop and pins the tool's behavior.

## 6. Size audit

New installed instruction text: ~14 lines (architect: criterion shape + self-lint) + ~10
lines (reviewer: plan-critique mode) + ~2 lines (orchestrator: plan-gate dispatch) ≈ 26
lines across the two-plus agent files, within the footprint the house rules set. New repo
content: `tools/lint_acceptance_checks.py` and its bash test, plus this spec. New agents:
zero. New routes: zero. New gates: zero. New hooks: zero. `install.sh`: untouched.

## Decision inventory

**Consequential**

1. **What "executable check per task" means for judgment-heavy criteria.** Options: (a)
   force every criterion to have an executable check — rejected: it manufactures the exact
   theater we are killing (a `test -f spec.md` dressed as "reads clearly"); (b) leave
   criteria as prose — rejected, it is the status quo we are fixing; (c) a two-tag taxonomy
   — mechanical criteria carry executable checks, judgment criteria are labeled and routed
   to a named judge against a stated bar. **Chosen: (c)**, but worked one level deeper than
   the taxonomy — the unifying property is *falsifiability*, not *executability*. Both tags
   must be falsifiable; they differ only in which instrument (command vs. named judge)
   returns "no." This reframe is what makes the judgment side lintable at all (an empty bar
   is a tautology too, A2) and exposes the taxonomy's own gaming vector (A3). *Resolved.*
2. **Where the lint runs and who runs it.** Options: orchestrator (impossible — no Bash),
   verifier (has Bash but post-build, catches theater too late), reviewer (Bash, read-only,
   already the gate-time critic). **Chosen: reviewer at the plan gate**, because a
   tautological criterion is a stopped-short tell the reviewer already owns one artifact
   later, and this reuses an existing gate with no new dispatch — dissolving the "new
   route?" tension. The verifier stays the unchanged post-build backstop. *Resolved.*
3. **A declared criterion format.** The tool can only lint what it can parse, and free
   prose is not parseable without NLP. Options: (a) leave prose and accept a toothless,
   reviewer-eyes-only lint — rejected, it forfeits the determinism that is the entire value
   of the port; (b) restructure whole plans — rejected as over-heavy; (c) tag + `Check:` /
   `Judge:`/`Bar:` lines on acceptance criteria only. **Chosen: (c)**, scoped to criteria,
   additive to the `Run:/Expected:` shape the architect already half-writes, and it
   strengthens the verifier's existing contract rather than competing with it. *Resolved.*
4. **Block vs. warn, per class.** Options: uniform-advisory (ringer's posture) or split.
   **Chosen: split on determinism** — L1/L2/L3 load-bearing (block-equivalent, routed to
   the gate as decision content), A1–A4 advisory-with-explanation. Reasoning: uniform
   advisory would make the flags cost-free to ignore, the precise anti-pattern the
   decision-discipline design named against its own flags; uniform blocking would let a
   heuristic false positive (A1) or a judgment call (A3) hard-stop a sound plan.
   Determinism is the honest dividing line. *Resolved.*
5. **The lint class list.** Ported L1 (tautological), L2 (silent) directly; adapted L3
   (mechanical-without-check) and A1 (unfalsifiable-phrasing); added the team-specific A2
   (empty-judgment), A3 (mislabeled — the taxonomy's gaming vector), A4 (uncertified-check-
   overreach — ties to the gap-detection label); **dropped** ringer's file-pointer class
   (already covered by writing-plans no-placeholders) and write-collision class (this team
   builds sequentially, no parallel worktrees — the hazard is structurally absent).
   *Resolved.*
6. **Tool language: Python 3 stdlib vs. bash.** Chosen **Python 3 stdlib**, because the
   load-bearing classes need shell-token analysis (`shlex`) to avoid false positives on a
   *blocking* lint, and a bash/grep port reintroduces exactly that risk; Python is the
   prior art's language and is standard on the target machines; absence degrades to eyes-
   only with a flag. **But this is a genuine either/or for the human** — it introduces a
   Python toolchain to a bash+jq repo, a maintainability direction a second good engineer
   could resolve the other way (accept coarser bash detection to keep one toolchain). *Open
   for the gate.*

**Trivial** (decided and moved past)

- Tool path `tools/lint_acceptance_checks.py` — *not consequential:* a new `tools/` dir is
  the conventional home; no contract rides the location.
- Test as bash (`tests/test_acceptance_lint.sh`) not Python unittest — *not consequential:*
  matches the repo's existing all-bash test suite and the `for t in tests/test_*.sh` loop;
  the tool-under-test is still Python.
- Tool output format (`BLOCK/WARN CLASS AC-N why good:`) — *not consequential:* internal
  contract between the tool and its own test/reviewer; freely revisable.
- Reviewer mode named "plan-critique" paralleling "spec-critique" — *not consequential:*
  naming, chosen for symmetry with the existing mode.
- Tool referenced by manifest repo-path rather than installed — *not consequential:* it
  simply reuses the pattern the gap-detection design already established and validated.

## Open question for the human (gate)

**Decision 6 — tool language.** Python 3 stdlib (precise shell-token analysis, safe for a
blocking lint, prior-art-aligned) versus bash-only (one consistent toolchain, coarser
detection, higher false-positive risk on the blocking classes). Recommended: Python, with
graceful degrade to reviewer-eyes-only when `python3` is absent. This is the one decision
whose resolution is a real direction call rather than a derivable one.
