# Org Skill Layer — Design

**Date:** 2026-07-09
**Status:** Draft for human review
**Prior art:** `2026-07-07-ai-agent-team-design.md` (roster, permissions, gates — unchanged by this spec)

## Goal

Make the skill layer a first-class part of this repository: right-sized skills preloaded
per role, zero third-party skill dependencies, and an owned expert-panel capability —
versioned, installed, validated, and drift-checked exactly like the agents.

## Problems this solves

1. **Skills are outside the source of truth.** The repo validates that skills *resolve* at
   install but does not own their content. A new machine cannot be deployed from this repo
   alone; skill content is unversioned and undiffable.
2. **Four preloads ride an unpinned third-party plugin** (superpowers 6.1.1:
   `writing-plans`, `test-driven-development`, `verification-before-completion`,
   `brainstorming`). Everything else in this repo is pinned; these update underneath us.
3. **Preloads are heavy and compliance-styled.** Skills written for a general session carry
   trigger phrases and enforcement rhetoric that are dead weight when preloaded into a
   role-scoped agent whose hooks already enforce hard boundaries. Current preload weight:
   builder ~1,019 lines, ticketer ~1,658, verifier ~829 — before reading one line of task code.
4. **The builder has no debugging discipline** despite the designed verifier/reviewer →
   builder repair loops (up to two before escalation).
5. **The expert-panel model is valued but not owned.** The spec and business panels come
   from the SuperClaude framework (not installed on this machine), are single-context
   roleplay prone to expert convergence, and carry framework cruft irrelevant to this harness.

## Non-goals

- No changes to agent roster, models, permissions, hooks, or cost accounting beyond each
  agent's `skills:` line and situational-skill list.
- No automatic panel convening at gates (parked; human convenes until usage shows a pattern).
- No rosters beyond `spec` and `business` (parked: security, architecture, operability/SRE).
- No changes to the built-in skills the team uses (`verify`, `security-review`).

## Design

### 1. Ownership and installation

`skills/` in this repo is the canonical org skill layer. `install.sh` installs it to
`~/.claude/skills/` with full parity to agent handling:

- Validation before any copy: YAML frontmatter with `name` + `description`, `name`
  matching its directory, no skill exceeding its declared size ceiling (below), and every
  relative link in a SKILL.md resolving to a file that exists in the repo — a dangling
  `references/` link fails the install rather than failing mid-dispatch at runtime.
- Timestamped backups of any file about to be replaced; full restore on partial failure.
- Checksums recorded in the build manifest; `install.sh --check` reports DRIFT / STALE /
  NEW for skills exactly as it does for agents.
- A skill referenced by any agent that is missing from `skills/` fails the install.

**Renames to avoid shadowing built-in skills:** org `code-review` → `reviewing`
(the client ships a built-in `code-review`); the new verification skill is named
`verifying` (distinct from built-in `verify`). The reviewer's and verifier's frontmatter
update in the same commit as each rename — no phase leaves an agent referencing a name
that does not resolve.

End state: 16 owned skills (10 distilled, 5 authored, 1 panel engine), no plugin
dependencies, superpowers uninstalled.

### 2. House authoring standard

Written as `docs/skill-style.md` and applied to every skill in this repo:

- **Knowledge, not compliance.** Hooks enforce "can't"; the roster and dispatch decide
  "when". Preloaded skills carry only "how" and "what good looks like". No trigger-phrase
  sections, no MANDATORY/Iron-Law rhetoric, no red-flag rationalization tables.
- **Job in the first three lines.** A reader (human or model) knows what the skill is for
  without scrolling.
- **Org policy is sacred and visible.** Every normative org rule is kept verbatim on a line
  marked `[ORG POLICY]`, e.g.:
  `[ORG POLICY] Test coverage must be ≥90% for all production code.` Distillation may move or reformat policy lines, never weaken or
  drop them. Each distilled skill's plan task includes a before/after inventory of its
  `[ORG POLICY]` lines; a dropped line is a review-blocking defect.
- **Policy boundary rule:** each org rule lives in exactly one skill. Numeric mandates and
  org procedures live in the role's standards skill (e.g. coverage policy in
  `coding-standards`); craft skills (`tdd`, `debugging`) teach technique and may reference
  policy but never restate it. This prevents the same rule drifting into two versions.
- **Long material goes to `references/`**, read on demand — not into preload weight.
- **Size targets:** most skills 30–100 lines; hard ceiling 150 except `reviewing`,
  `convene-panel`, and `ux-to-ui-design` (ceiling 200). The installer warns at ceiling.
- **Questionable policy gets flagged, not silently preserved or dropped.** Flags accumulate
  in the implementation plan's decision queue (Section 9) for human ruling.

### 3. Authored skills (five)

| Skill | Preloaded by | Distilled from | Target |
|---|---|---|---|
| `interviewing` | architect (situational) | Matt Pocock `grilling` + the gate flow of superpowers `brainstorming` | ~40 lines |
| `planning` | architect (always) | superpowers `writing-plans`: exact-file tasks, checkbox tracking, self-review pass | ~90 lines |
| `tdd` | builder | Matt Pocock `tdd`: seams, tautological/horizontal-slicing anti-patterns, red-green loop rules | ~60 lines |
| `verifying` | verifier | superpowers `verification-before-completion`: evidence before claims, exact command + output per criterion | ~50 lines |
| `debugging` | builder | Matt Pocock `diagnosing-bugs`: feedback-loop-first, red-capable command criterion, minimise, ranked falsifiable hypotheses, tagged instrumentation, cleanup | ~90 lines |

Core content decisions already made: `interviewing` keeps the facts-vs-decisions split
(look up facts in the codebase; put decisions to the human one at a time). `debugging`
keeps the Phase-1 completion criterion (one already-run, red-capable, deterministic, fast,
agent-runnable command) — it is the discipline the repair loop needs most.

### 4. Distilled skills (ten)

| Skill | Now | Target | Notes |
|---|---|---|---|
| `coding-standards` | 132 | ~80 | Numeric mandates kept as `[ORG POLICY]` per the Section 9 rulings: coverage tier-scoped, spec-first moved out of builder preload |
| `secure-secrets` | 516 | ~120 | Long tool/pattern lists → `references/` |
| `reviewing` (was `code-review`) | 347 | ~150 | Renamed; reviewer frontmatter updated same commit |
| `plan-review` | 95 | ~80 | Already close to right-sized; checklist form kept |
| `task-verification` | 690 | ~100 | Boundary: defers all evidence discipline to `verifying`; keeps only Asana-specific closure procedure (criteria mapping, subtask states). Mechanics → `references/` |
| `write-ticket` | 564 | ~150 | Ticket format rules are `[ORG POLICY]`; walkthroughs → `references/` |
| `review-ticket` | 404 | ~100 | Same treatment |
| `writing-business-requirements` | 442 | ~150 | Requirement-quality rules kept; templates → `references/` |
| `audit-requirements-document` | 209 | ~120 | Pattern catalog kept; worked examples → `references/` |
| `ux-to-ui-design` | 344 | ~200 | Higher ceiling; visual-craft content is the skill's substance |

**Exemplar-first rule:** Phase 3 begins with one skill (`coding-standards`) distilled and
human-approved before the remaining nine are batch-processed. The exemplar calibrates how
aggressive "distill hard" is in practice; the other nine follow its approved pattern.

### 5. Preload budgets

| Role | Preloads after | Budget (lines) | Was |
|---|---|---|---|
| builder | coding-standards, tdd, secure-secrets, debugging | ≤ 400 | ~1,019 |
| architect | planning (always) | ≤ 100 | 174 |
| verifier | verifying, task-verification | ≤ 200 | ~829 |
| reviewer | reviewing | ≤ 150 | 347 |
| scribe | writing-business-requirements, audit-requirements-document | ≤ 300 | ~651 |
| ticketer | write-ticket, review-ticket, task-verification | ≤ 400 | ~1,658 |
| ops | secure-secrets | ≤ 120 | 516 |
| deployer | verify (built-in) | n/a | n/a |

Budgets are acceptance criteria for Phase 3, measured by `wc -l` over each role's preload
set. A budget miss is resolved by moving content to `references/`, never by dropping
`[ORG POLICY]` lines.

### 6. Panel engine (`convene-panel`)

One skill owns the mechanics; rosters are data.

**`skills/convene-panel/SKILL.md` (~120 lines):**

- **Three modes:** discussion (experts build on each other), debate (experts attack the
  strongest claims), socratic (experts only ask questions). Default: discussion.
- **Required dissent:** in every mode, every expert must end with their single strongest
  objection to the artifact — even if they are broadly positive. This is the structural
  fix for roleplay convergence.
- **Synthesis format:** consensus points / contested points (with who disagrees and why) /
  open questions / prioritized recommendations. Contested points are never averaged into
  false consensus.
- **Roster file format:** one expert per section — name, framework, methodology, critique
  focus (one sentence in the expert's voice). The engine validates a roster has 3–9 experts
  before convening.
- **Expert selection:** convene the full roster by default; the convener may name a subset
  when the artifact clearly doesn't touch an expert's domain.

**Rosters shipped:** `rosters/spec.md` (Wiegers, Adzic, Cockburn, Fowler, Nygard, Newman,
Hohpe, Crispin, Gregory, Hightower) and `rosters/business.md` (Christensen, Porter,
Drucker, Godin, Kim & Mauborgne, Collins, Taleb, Meadows, Doumont) — ported faithfully
from SuperClaude, minus wave/persona/MCP cruft.

**Two invocation modes:**

- **Standalone** (any session): single-context roleplay. Cheap; the default.
- **Dispatched** (any session holding the Agent tool): one subagent per expert, receiving
  only the artifact and that expert's roster entry — no expert sees another's output.
  The convener synthesizes and states estimated cost before dispatching. This is the
  high-stakes mode; the orchestrator may use it at gates when the human asks.

Extending the model = adding a roster file. No engine changes.

### 7. Upstream watch

A monthly review of the sources this layer distilled from, so owned skills don't go stale:

- **Procedure:** `docs/upstream-watch.md` — pinned source list (`obra/superpowers`,
  `mattpocock/skills`, `SuperClaude-Org/SuperClaude_Framework`), a watermark file recording
  the last-reviewed commit/release per source, and the report format.
- **Report:** `docs/upstream-reports/YYYY-MM.md` — per notable upstream change: adopt /
  adapt / ignore, with one-line rationale and citation. Notability filter: changes to
  skills this layer was distilled from, or new upstream skills addressing a problem this
  team's roles face; everything else is a one-line "reviewed, not applicable" entry.
  Nothing is auto-adopted; the report is input to a human decision.
- **Execution:** a scheduled monthly Claude Code task (setup one-liner documented in the
  README); the procedure is written so a manual run produces the identical artifact.

### 8. Build order and acceptance

Each phase leaves `install.sh --check` green and no agent referencing a nonexistent skill.

- **P1 — Foundations:** `docs/skill-style.md`; installer skill support (validation,
  manifest, drift, backup); test suite extended to cover skill validation.
  *Accept:* `--check` green including skills; all tests pass.
- **P2 — Authored five + rewiring:** the five authored skills; agent `skills:` lines and
  situational lists updated; superpowers references removed from `agents/`.
  *Accept:* `grep -r superpowers agents/` is empty; install green; one toy-task builder
  dispatch with a **planted defect** (a seeded failing behavior the plan doesn't mention)
  exercises `tdd` on the feature and `debugging` on the defect — a healthy toy task
  cannot verify a debugging skill.
- **P3 — Distill ten:** exemplar (`coding-standards`) first, human-approved, then the
  batch; `code-review` → `reviewing` rename with same-commit frontmatter update.
  *Accept:* every role within budget (Section 5 table); `[ORG POLICY]` inventory diff
  clean per skill; policy flags logged in the decision queue; install green.
- **P4 — Panel engine:** `convene-panel` + both rosters.
  *Accept:* standalone convening of the spec roster against this very spec produces
  per-expert output with required dissent and a synthesis separating contested points;
  dispatched-mode dry run documented (prompt template + cost estimate, no full run required).
- **P5 — Watch + closeout:** upstream-watch procedure + first report + schedule;
  README updates (deploy section no longer lists skills as an external dependency);
  full team shakedown per README; superpowers plugin uninstalled.
  *Accept:* report #1 exists; the shakedown exercises **at least one preloaded skill per
  role** (a ticket drafted, a document written, a criterion verified — not just the builder
  path); plugin absent; `--check` green.

### 9. Policy decision queue

Rulings happen at plan review, not during distillation. Flags found during Phase 3 are
appended here with the distiller's recommendation.

**Ruled 2026-07-09:**

1. **Test coverage — scoped by tier.** `[ORG POLICY]` becomes: ≥90% coverage for
   standard/large-tier work; trivial/small-tier work requires TDD (test-first at agreed
   seams) but no numeric threshold. The builder reads the tier from its dispatch.
2. **Spec-first — scoped to non-team use.** The rule leaves the builder's preload (the
   architect → gate → builder route guarantees it structurally); it stays stated in
   `docs/skill-style.md` for anyone using these skills outside the team, where no
   orchestrator enforces sequencing.

### 10. Risks

- **Distillation drops a load-bearing rule.** Mitigated by the `[ORG POLICY]` inventory
  diff per skill and the exemplar-first calibration step.
- **Owned skills drift stale against upstream ideas.** Mitigated by the upstream watch.
- **Renames break a stale machine.** Mitigated by same-commit frontmatter updates, install
  atomicity with restore, and `--check` drift detection.
- **Dispatched panels are expensive.** Mitigated by standalone-by-default, cost statement
  before dispatch, and no auto-convening.

## Parking lot

- Additional rosters: security (reviewer), architecture (architect, large tier),
  operability/SRE (deploy gate).
- Auto-convening panels at specific gates once manual usage shows where they earn it.
- Model downshifts for panel experts (e.g. Haiku experts, Opus synthesis).
