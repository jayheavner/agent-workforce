# Dispatch Telemetry — Evidence-Based Model Routing — Design

**Date:** 2026-07-13
**Status:** Approved 2026-07-13 — human directed work-to-completion in-session; plan-review
passed same day (three plan-level conditions, all discharged in the implementation plan).
D2 resolved: the recommended defaults-map option, amended to a **committed** file (see D2).
**Prior art:** `2026-07-08-exact-closeout-cost-accounting-design.md` (the PostToolUse(Agent)
cost hook, the per-session cost file, the sticky-`unavailable` fail-open pattern, per-session
file naming + newest-wins, `model-rates.json` as the no-numbers-in-code rates source — this
design extends all of it); `2026-07-12-gap-detection-capability-loop-design.md` (records the
scribe writes at the orchestrator's direction, one small file that merges cleanly across
installs, "counts only once in canonical main," disclose-at-gate — the telemetry record reuses
this pattern wholesale); `2026-07-10-decision-discipline-design.md` (the repair-loop and
critic-loop semantics that define "first try," the two-questions block); `2026-07-07-ai-agent-team-design.md`
(roster, routes, gates — unchanged).
**External prior art:** Nate Jones' *Ringer* swarm orchestrator, reviewed and approved for
idea-reuse by Jay 2026-07-13. Two ideas adopted: (1) *first-try pass rate is the routing signal —
route on evidence, not vibes* (`ringer.py` aggregates `first_try_pass_rate`, `pass_rate`,
`median_*` per model); (2) the model-identity taxonomy's evidence precedence,
**harness-reported > config-resolved > unattributed** (`docs/TAXONOMY.md`) — drift is surfaced,
never silently credited.

## Goal

Turn every dispatch the team already runs into durable evidence for two questions the team
currently answers by judgment:

1. **Which model should each role run on, per task tier?** Accumulate first-try pass rates and
   costs per (role, model, tier) so the orchestrator's downshift/upshift table
   (`agents/orchestrator.md`) can be recalibrated on a local scoreboard instead of intuition.
2. **Did the harness actually run the model we pinned?** The frontmatter pins a model and the
   installer warns, but nothing at runtime confirms the pin was honored
   (`CLAUDE_CODE_SUBAGENT_MODEL` can override it silently). Record what actually ran, as
   harness-reported evidence, and surface any drift from what was requested.

Both collapse into **one artifact: the dispatch outcome record.** The scoreboard is a query over
those records; drift is a field in each record. No new agents, no new routes — a small extension
to the existing cost hook plus instruction text on the orchestrator, and one read-only ops query.

## Motivating scenario

The orchestrator's table says "builder: never downshift — quality floor for code" and "researcher:
downshift to haiku for single-fact lookups." Those are reasonable guesses. But over six weeks the
team has run 40 builder dispatches; nobody can say whether the sonnet default actually clears
verify + review first-try often enough, or whether the second-loop opus upshift is pulling its
weight, because the evidence — first-try pass, repair loops, cost — evaporated with each session's
context. Separately, one week a colleague's shell had `CLAUDE_CODE_SUBAGENT_MODEL=claude-haiku-4-5`
exported; every "opus" architect dispatch silently ran on haiku, the specs were thin, and no gate
line ever said so. Both failures share a cause: **the record of what a dispatch requested, what
actually ran, and whether its output survived downstream checks is never written down.** This
design writes it down.

## Non-goals

- **No new agent, no new route, no new permission.** The hook gains a few fields; the orchestrator
  gains instruction text; the scribe's existing closeout dispatch gains one artifact. That is the
  whole installed footprint.
- **No live HUD, no web server, no dashboard.** The scoreboard is a read-only script plus a
  documented `jq` query, run by a human or ops when recalibrating the table.
- **No automatic table changes.** The scoreboard produces evidence; changing the routing table is a
  human edit to `agents/orchestrator.md`, exactly as today. Nothing self-tunes.
- **No change to cost accounting math or its fail-open contract.** Telemetry is strictly additive;
  a malformed or missing outcome record must never block a dispatch or alter a cost figure.
- **Not per-token model benchmarking.** This measures *this team's* routing outcomes, not model
  quality in the abstract.

## Design overview

One record schema, assembled from two sources because no single actor holds every field:

- The **hook** knows the mechanical facts at dispatch-completion time — role, tokens, cost, and now
  the **requested** model (from the dispatch's `tool_input.model`). The **resolved** (actually-ran)
  model is already on disk: it is the model key(s) under each dispatch entry in the cost file,
  written from the harness's own `.message.model` records. The hook's only new job is to stamp
  `requested_model` alongside them.
- The **orchestrator** alone knows the *verdict* facts — task identity, tier, whether a dispatch was
  the first attempt or a repair loop, and whether its output ultimately passed. These are unknowable
  when the hook fires (the verdict comes from *downstream* checkers, later in the session).

Because the orchestrator has no Write tool and its only sanctioned write channel is the **scribe**
(confirmed: `hooks/agent-team-policy-lib.sh:217` confines the scribe to `docs/`, `plans/`,
`doc-inventory/`, `STATUS-*.md`, `scratchpad/`), the record is **assembled and written by the
scribe at closeout** — the same dispatch that already writes the status note. The scribe *reads* the
cost file (reads are unrestricted) for the mechanical half and receives the verdict half in its
dispatch prompt, then writes one outcome record per dispatch to the project's `docs/telemetry/`.
Records flow to the canonical repo by ordinary git PR and count for calibration only once in
canonical main — identical to how `docs/gaps/` records flow and count (§4 of the gap-loop design).

§1 defines the record. §2 is the hook change. §3 is the orchestrator + scribe closeout change. §4 is
the model-identity/drift rules. §5 is the scoreboard query. §6 is the fail-open contract. §7 is
testing/install. §8 is the decision inventory — including the one open question worked in full.

## 1. The dispatch outcome record

One JSON object per dispatch, written as one line of JSONL. Schema v1:

```json
{
  "schema": 1,
  "logged_at": "2026-07-13T18:20:05Z",
  "session_id": "e41a4464-ba82-4494-8a7f-4637836069fe",
  "project": "/Users/jay/claude/csv2json-2",
  "task_slug": "csv2json-cli",
  "tier": "small",
  "dispatch_id": "a903a11b800810642",
  "role": "builder",
  "requested_model": "claude-sonnet-5",
  "resolved_model": "claude-opus-4-8",
  "model_drift": true,
  "sequence": "first",
  "verdict": "pass",
  "tokens": 46880,
  "cost_usd": 0.6864,
  "cost_available": true
}
```

Field sources and meaning:

| Field | Source | Notes |
|---|---|---|
| `session_id`, `project` | cost file / dispatch context | join key; `project` is the cwd |
| `task_slug`, `tier` | orchestrator (in the scribe prompt) | orchestrator-assigned identity + triage tier |
| `dispatch_id` | cost file key (`agentId`) | joins the two halves |
| `role` | cost file `agent_type` | one of the nine specialists |
| `requested_model` | hook (`tool_input.model`), else role pin | what was asked for — see §4 |
| `resolved_model` | cost file `.dispatches.<id>.models` keys | **harness-reported — authoritative** |
| `model_drift` | derived, `normalize(requested) != normalize(resolved)` | `null` when either side unknown |
| `sequence` | orchestrator | `first` \| `repair-1` \| `repair-2` \| `n/a` |
| `verdict` | orchestrator | `pass` \| `fail` \| `escalated` \| `n/a` |
| `tokens`, `cost_usd` | cost file dispatch entry | `null` when cost file is `unavailable`/absent |
| `cost_available` | derived | `false` records still carry role/model/verdict |

**`sequence` and `verdict` are the routing signal.** They are meaningful only for dispatches whose
output passes through a checker loop: the **builder** (checked by verifier + reviewer, up to two
repair loops per `agents/orchestrator.md` Rules) and the **architect** spec dispatch (checked by the
spec critic + gate, its own two-loop counter per the decision-discipline design). For every other
role both are `n/a` — those rows still carry model/cost/drift, which is useful telemetry, but they
have no "first-try pass" concept. `first_try_pass` is **not stored**; it is derived at query time as
`sequence == "first" AND verdict == "pass"`, exactly as Ringer derives `first_try_pass_rate` from
stored `verdict` + attempt number rather than storing a boolean (`ringer.py` aggregation).

Worked example of the sonnet→opus repair upshift the table encodes: a builder that fails on the
sonnet default then passes on the opus second-loop upshift produces **two** rows — `{role:builder,
resolved_model:sonnet, sequence:first, verdict:fail}` and `{role:builder, resolved_model:opus,
sequence:repair-1, verdict:pass}`. The scoreboard then correctly credits neither model with a
first-try pass it did not earn, and the sonnet first-try-fail is exactly the evidence that tells the
human whether "builder never downshift" is paying for itself.

## 2. Hook change — stamp the requested model (`hooks/agent-team-cost.sh`)

The cost hook already writes, per dispatch, `agent_type` (role), the per-model token/cost breakdown
(whose keys are the **resolved** models), and the totals. The only addition: capture the dispatch's
requested model and store it on the dispatch entry.

- Extract `tool_input.model` from the hook stdin (a new field read alongside the existing
  `tool_response.agentId`/`agentType`). When the orchestrator passed a per-dispatch `model` override,
  it appears here; when it did not (the dispatch ran on the frontmatter pin), it is absent.
- Add one field to each dispatch entry: `"requested_override": "<value>"` or `null`. Store it raw;
  normalization and the drift comparison happen at query time (§4), keeping the hook's job purely
  mechanical and its recognition rules untouched.
- **Discovery to confirm in the plan (not yet observed on a live transcript):** that an `Agent`
  dispatch's `tool_input` carries `model` when the orchestrator overrides it. The existing cost spec
  verified `tool_response.resolvedModel`/`agentType` against a real transcript; this field has not
  been. The plan's first step is to confirm it against a captured payload. **Fail-open regardless:**
  if `tool_input.model` is absent for any reason, `requested_override` is `null` and drift for that
  dispatch is resolved against the role pin (§4) or reported `null` — never an error, never a
  changed cost number.

This is the entire change to the hook. Its recognition rules, dedup, pricing, sticky-`unavailable`
marker, and per-session file all stay exactly as specified in the 2026-07-08 design and its
2026-07-09 amendments. The new field lives beside the existing bookkeeping and is ignored by every
existing code path.

## 3. Orchestrator + scribe closeout change

### Orchestrator (instruction text, ~12 lines, added to `## Closeout cost report` or a sibling
`## Dispatch telemetry` section)

> **Dispatch telemetry.** At the FINAL gate of any *routed* task (small/standard/large — not the
> trivial tier, which has no checker loop), when you dispatch the scribe for the closeout status
> note, extend that same dispatch to also record the task's dispatch outcomes. Provide the scribe,
> for each builder and architect work dispatch in the task: its `agentId`, the `task_slug` and
> `tier` you assigned at triage, its `sequence` (`first` / `repair-1` / `repair-2` — you already
> track this to enforce the two-loop bound), and its `verdict` (`pass` if its output was accepted
> downstream without rework, `fail` if it triggered a repair loop, `escalated` if it went to the
> human unresolved). Instruct the scribe to write one telemetry record per dispatch to
> `docs/telemetry/` per that directory's README schema, joining your verdict facts to the mechanical
> facts (role, models, tokens, cost) it reads from the session cost file. This is one added artifact
> on an existing dispatch, not a new dispatch. If the cost file is unavailable or absent, the scribe
> still records role/verdict/requested-model with cost and resolved-model marked unknown — telemetry
> is best-effort and never a gate. Every final-gate summary already carrying a `gaps:` line also
> carries `telemetry: <record count> records` (or `telemetry: skipped — <reason>`), so a dropped
> write is visible, not silent.

The trivial tier is excluded by construction: it runs one dispatch, no gate, no checker loop, so it
has no first-try-pass concept and forcing a closeout scribe dispatch would contradict its "one
dispatch, no route" design. Trivial dispatches still land in the cost file for cost accounting.

### Scribe (instruction text, ~4 lines, added to the status-note duty)

> **Telemetry duty:** when the orchestrator's closeout dispatch includes a telemetry block, also
> write one record per named dispatch to `docs/telemetry/` per its README schema. Read the session
> cost file at `$AGENT_TEAM_COST_DIR` (default `~/.claude/logs/agent-team-cost/`) or the path the
> orchestrator gives you, match each dispatch by `agentId`, and copy its role, resolved model(s),
> requested override, tokens, and cost. Fields the cost file lacks (it is `unavailable`, absent, or
> missing that `agentId`) are written `null` with `cost_available: false`. Never invent a number.

`docs/telemetry/` is inside the scribe's allowed write tree — no policy change is required.

## 4. Model identity and drift

Adopting Ringer's precedence directly: **harness-reported wins.** The scoreboard buckets every
outcome by `resolved_model` — the model the harness actually ran, taken from the transcript's own
`.message.model` records (already the cost file's per-dispatch model keys). Cost and outcome
attach to what ran, never to what was hoped for.

- **Normalization** before any comparison: strip a trailing `[1m]` (the cost hook already does this
  for rate lookup) and treat the result as the model identity. Both `requested` and `resolved` are
  normalized the same way.
- **`requested_model`** for the record is `requested_override` when the hook captured one, otherwise
  the role's frontmatter pin. So a dispatch that ran on its default is still checked against the pin
  it was supposed to honor — which is the whole point of idea (2). Where the pin comes from is the
  one open recommendation (§8, Decision D2): the recommended path is an installer-generated
  `hooks/agent-model-defaults.json` (the installer extracts each agent's `model:` pin from its
  frontmatter and writes + validates the map), so the pin can never silently diverge from the
  frontmatter and drift is computable for *every* dispatch, not only overridden ones.
- **`model_drift`** = normalized `requested_model` != normalized `resolved_model`. `null` when either
  side is unknown (e.g. cost file unavailable, or `requested` unresolved under the lighter D2 option).
  A drift-true record is never counted as evidence for the requested model; it counts for the model
  that ran and is separately visible in the scoreboard's drift column — surfaced, never credited.
- **Quarantine (Ringer's fixture rule, adapted):** the synthetic error model `<synthetic>` (already
  skipped by the cost hook) and any `resolved_model` absent from `model-rates.json` are excluded from
  first-try/pass-rate aggregation and flagged in a scoreboard `unattributed` line, never silently
  folded into a real model's record. Test-fixture model names live only under `tests/fixtures/` and
  never reach a real `docs/telemetry/` directory.

## 5. The scoreboard — `tools/agent-team-scoreboard.sh` + documented query

A read-only script (new dir `tools/`, run in place from the repo; nothing installed to
`~/.claude/`, nothing invoked by the harness). It slurps every `*.jsonl` under a telemetry root
(default: the repo's `docs/telemetry/`; a path argument overrides) and prints one text table:

```
role       resolved_model     tier      n   first-try%  pass%   median $   drift
builder    claude-sonnet-5    small    23      74%       91%     0.18       0
builder    claude-opus-4-8    small     4      —         100%    0.44       0
architect  claude-opus-4-8    standard 11      82%       100%    0.31       2
...
(unattributed: 1 record with a model not in model-rates.json; 3 drift records — see --drift)
```

Metrics per (role, resolved_model, tier) group: `n` (records), `first-try%`
(`sequence==first` → `pass`/total), `pass%` (any-sequence `pass`/total), `median $` (median
`cost_usd`, `null` costs excluded), `drift` (count of `model_drift==true`). No ranking, no tiers, no
promotion ladder — this is evidence for a human recalibrating the table, not an automated judge.

For ad-hoc use the README documents the common one-liner (no median, which is why the script earns
its keep):

```
jq -s 'group_by([.role,.resolved_model,.tier]) | map({key:(.[0].role+"/"+.[0].resolved_model+"/"+.[0].tier),
  n:length, first_try:(map(select(.sequence=="first" and .verdict=="pass"))|length)})' docs/telemetry/*.jsonl
```

Because records are per-session files that merge cleanly by git (one file, append-only within a
session), the aggregate is simply "every file in the tree" — the cost-file same-directory-collision
limitation does **not** apply here: there is no newest-wins read, only a full-tree sum.

## 6. Fail-open contract

Telemetry never blocks a dispatch, never changes a cost figure, never fails a gate.

- **Hook:** the new `tool_input.model` read is additive; absent/garbage → `requested_override:null`.
  No new recognition rule, so nothing new can trip the sticky-`unavailable` marker; cost math is
  byte-for-byte unchanged when the field is absent (regression-tested, §7).
- **Scribe:** cost file `unavailable`/absent/missing-the-agentId → records still written with `null`
  cost/resolved-model and `cost_available:false`. A scribe dispatch that errors leaves the task to
  close normally; the orchestrator's `telemetry: skipped — <reason>` line makes the miss visible.
- **Scoreboard:** a malformed JSONL line is skipped with a counted warning, never aborts the run;
  an empty tree prints an empty table, not an error.

## 7. Testing and install validation

Determinism rule: everything installed or shipped is validated by `install.sh` and covered by a
bash test in `tests/`.

- **Extend `tests/test_cost_hook.sh`** (the hook change lives in the same file):
  1. `requested_override` stamped: a fire whose `tool_input.model` is `claude-sonnet-5` while the
     dispatch's transcript resolves to `claude-opus-4-8` → the dispatch entry carries
     `requested_override:"claude-sonnet-5"`; resolved model key stays `claude-opus-4-8`.
  2. Absent override → `requested_override:null`.
  3. **Regression:** the existing good-fixture totals are **byte-identical** to before the change
     (proves cost math untouched) — assert the same `0.1165` grand total already in the file.
- **New `tests/test_scoreboard.sh`** with a `tests/fixtures/telemetry/` directory: a handful of
  crafted records exercising first-try pass, a repair loop (fail then pass), a drift-true record, an
  `n/a` support-role record, and one `resolved_model` absent from the rates file. Assert the computed
  `first-try%`, `pass%`, `median $`, `drift` count, and the `unattributed` line against hand
  computation written in the test header (the executable-spec convention the cost test uses).
- **New `docs/telemetry/README.md`** — the record schema (this §1), the `<kind>` of quarantine
  rules, and the "counts only in canonical main" rule. Repo content, not installed instruction text,
  exactly like `docs/gaps/README.md`.
- **`install.sh`:** add `bash -n tools/agent-team-scoreboard.sh` and `bash tests/test_scoreboard.sh`
  to the existing validate block. Per the D2 resolution: regenerate the role→pin map from each
  `agents/*.md` `model:` line, fail if it differs from the committed
  `hooks/agent-model-defaults.json`, shape-check that every pin is present in `model-rates.json`,
  and install + manifest the file exactly like `model-rates.json`.

Add one shakedown scenario to the README checklist: run a small task end-to-end, confirm
`docs/telemetry/<slug>--<session>.jsonl` appears with one record per dispatch, the builder row shows
`sequence:first`/`verdict:pass`, `resolved_model` matches the model that ran, and
`tools/agent-team-scoreboard.sh` renders a one-row-per-group table.

## 8. Decision inventory

### D1 — Where does the pass/fail verdict come from? (the required open question, worked in full)

**Consequential.** The verifier/reviewer verdicts live in the orchestrator's conversation, not in
any single Agent tool result. Options considered:

- **(A) Orchestrator emits a structured line a hook parses.** The orchestrator embeds a telemetry
  block in a dispatch's `tool_input` (prompt); a PostToolUse hook parses it and appends the joined
  record to a global log in `~/.claude/logs/`. *Rejected as primary:* it forces the cost hook — whose
  prime directive is "never corrupt a cost number" — to grow prompt-text parsing and a second write
  target, raising its risk surface; and it pollutes a dispatch prompt with hook-directed syntax the
  receiving agent must ignore. Its one genuine advantage (auto-aggregation on one machine without
  git) is not worth that risk given the routing table is recalibrated deliberately, not live.
- **(B) The orchestrator has the scribe write a separate outcome record.** *Recommended.* The scribe
  is the orchestrator's only sanctioned write channel and is already dispatched at closeout for the
  status note. It reads the mechanical half from the cost file and receives the verdict half in its
  prompt as ordinary content it is being told to write — no hook-parsing hack, no prompt pollution,
  no cost-hook risk.
- **(C) Record outcomes only for verifier dispatches, scraping their result text for verdicts.**
  *Rejected:* wrong grain (the routing signal is per *builder/architect* model, which a verifier
  verdict does not attribute), depends on unconfirmed result-text presence, and free-text scraping is
  exactly the fragility the cost hook's ethos forbids.

**Why B is not merely "preferred among three" but the one the constraints select:** I first checked
whether the binary dissolves — can the verdict be *inferred* from the dispatch sequence the hook
already sees (e.g. "a second builder dispatch after a verifier ran ⇒ the first attempt failed")? It
cannot reliably: task identity and "which builder attempt this is" are orchestrator-held, so a hook
would miscount a session that builds several independent components. The verdict is irreducibly
orchestrator-held. Then the permission topology decides the writer: I confirmed
(`hooks/agent-team-policy-lib.sh:217-236`) that the scribe can write only under
`docs/`/`plans/`/`doc-inventory/`/`STATUS`/`scratchpad`, and the orchestrator can write nothing —
so a *global* `~/.claude/logs/` outcome log can be written only by the hook (option A's cost), while
a *project* `docs/telemetry/` log is the scribe's natural, already-permitted output. Option B writing
to `docs/telemetry/` and flowing to canonical main by git is the same shape the gap-loop design
already ships and the human already reasons about. Resolved; recommended.

### D2 — How is `requested_model` known for a dispatch that ran on its frontmatter pin? (genuine either/or for the human)

**Consequential; the one decision I want Jay to focus on at review.** To flag drift on a dispatch
that used *no* per-dispatch override, the scoreboard must know the role's pin.

- **Recommended — installer-generated `hooks/agent-model-defaults.json`.** `install.sh` extracts each
  agent's `model:` pin from its frontmatter into a validated map. Drift is then computable for
  *every* dispatch, delivering idea (2) fully (it catches a `CLAUDE_CODE_SUBAGENT_MODEL` env override
  even when the orchestrator passed no override — the majority, and exactly the "did the harness
  honor the pin" case). The map cannot silently diverge from the frontmatter because the installer
  regenerates and validates it. Cost: ~10 lines of installer YAML-pin extraction + a shape check.
- **Lighter — override-only.** Store only `requested_override`; leave `requested_model`/`model_drift`
  `null` when no override was passed. Simpler (no installer change), but it checks pin-honoring only
  on overridden dispatches and misses the silent-env-override case on default-model dispatches — i.e.
  it delivers idea (2) only partially.

I tried to dissolve this into a non-choice and could not: the fuller check genuinely costs installer
complexity, and a reasonable engineer could accept the lighter check to keep the installer thin. This
is a real complexity-vs-completeness tradeoff for the human. **Recommendation: the installer-generated
map** — idea (2) is half the point of this design, and the lighter option leaves its main threat
model uncovered.

**Resolution (2026-07-13, at implementation):** the defaults-map option, with one mechanical
amendment discovered against the installer's actual manifest model. A purely installer-*generated*
file has no repo counterpart, so `install.sh --check` — which compares every manifest entry against
both the installed copy and the repo copy — would flag it `REMOVED — gone from the repo` on every
check. The same cannot-silently-diverge guarantee lands cleaner as a **committed**
`hooks/agent-model-defaults.json`: `install.sh` regenerates the map from `agents/*.md` frontmatter
at validate time and **fails loudly if the committed file differs** (the drift-test pattern already
used for the hash-identical coding-standards copies), shape-checks every pin against
`model-rates.json`, then installs and manifests it exactly like `model-rates.json`. Divergence is
impossible to install, and `--check` keeps working unmodified.

### D3 — One record schema assembled from two writers, vs. two record types

**Consequential (contract).** Chosen: one schema (§1), hook-half in the cost file, verdict-half joined
by the scribe into `docs/telemetry/`. *Reasoning:* "the scoreboard is a query over one record; drift
is a field in it" (the task's framing) is preserved — there is exactly one record shape to query. The
split is forced by *when* facts exist (mechanical at fire time, verdict only downstream), not chosen
for its own sake. Alternative — the scribe writes verdicts back into the hook's cost file — rejected:
it makes two writers co-own a file whose sticky-`unavailable` invariant and whole-file-rewrite
behavior are hook-owned, inviting a clobber. Separate files, single writer each.

### D4 — Scoreboard bucketed by `resolved_model`, not `requested_model`

**Consequential (contract).** Chosen: `resolved_model` (harness-reported). *Reasoning:* Ringer's
precedence and plain correctness — cost and outcome belong to the model that did the work; crediting a
requested model that was silently overridden would be a wrong number wearing an evidence label.

### D5 — Record all dispatches, or only builder/architect?

**Consequential.** Chosen: record all of a task's dispatches (the scribe reads them from the cost file
for free), with `sequence`/`verdict` populated only for builder/architect and `n/a` elsewhere.
*Reasoning:* the non-checked rows still carry model/cost/drift telemetry (useful for cost calibration
and drift detection) at near-zero marginal cost, while orchestrator bookkeeping is bounded to the two
roles whose routing we actually calibrate.

### D6 — Trivial tier excluded from telemetry

**Consequential (scope).** Chosen: exclude. *Reasoning:* no checker loop ⇒ no first-try-pass concept,
and a mandatory closeout scribe dispatch would contradict the trivial tier's "one dispatch, no route"
design. Cost accounting still covers trivial dispatches.

### Trivial decisions (one line each)

- Record format JSONL, one object per dispatch — not consequential: standard append/merge shape,
  matches Ringer's `runs.jsonl` and merges by git like `docs/gaps/`.
- Telemetry root default `docs/telemetry/` — not consequential: mirrors `docs/gaps/` naming; overridable.
- Scoreboard script placed in new `tools/` dir, not `hooks/` — not consequential: it is human-run, not
  harness-invoked; keeping it out of `hooks/` avoids implying registration.
- `requested_override` stored raw, normalized at query time — not consequential: keeps the hook's
  recognition rules untouched; normalization is a pure query concern.
- Field name `model_drift` boolean plus a scoreboard drift column — not consequential: naming.
- Per-session file naming `<cwd-slug>--<session_id>.jsonl` — not consequential: reuses the cost file's
  proven slug scheme.
- `telemetry:` gate line mandatory even when zero records — not consequential: same dropped-flag-becomes-
  visible pattern as the existing `gaps:` and manifest-build lines.

## Files to be changed

| File | Change |
|---|---|
| `hooks/agent-team-cost.sh` | Modify — read `tool_input.model`; store `requested_override` on each dispatch entry (§2). No other behavior change. |
| `hooks/agent-model-defaults.json` | Create — committed role→pin map, install-validated against `agents/*.md` frontmatter (D2 resolution). |
| `agents/orchestrator.md` | Modify — add the Dispatch telemetry closeout instruction and the `telemetry:` gate line (§3). |
| `agents/scribe.md` | Modify — add the telemetry duty to the status-note section (§3). |
| `docs/telemetry/README.md` | Create — record schema, quarantine rules, canonical-main counting rule (§1, §4). |
| `tools/agent-team-scoreboard.sh` | Create — read-only aggregation script (§5). |
| `tests/test_cost_hook.sh` | Modify — `requested_override` cases + cost-math regression assertion (§7). |
| `tests/test_scoreboard.sh` | Create — fixture-driven scoreboard tests (§7). |
| `tests/fixtures/telemetry/…` | Create — crafted outcome records for the scoreboard test. |
| `install.sh` | Modify — validate the scoreboard script + run its test; *(if D2 accepted)* generate + shape-check `agent-model-defaults.json` (§7). |
| `README.md` | Modify — a "Dispatch telemetry" subsection (log location, the documented query, the scoreboard) and one shakedown scenario. |

No file is deleted, moved, or overwritten via shell; every edit is in-place via Edit/Write. No new
packages: bash + jq only, both already required. The scribe writes only within its existing allowed
tree; no policy change.

## Acceptance criteria

1. **Requested model captured, cost math untouched.** Over the committed good fixture the cost hook
   now stamps `requested_override` per dispatch, and the good-fixture grand total is byte-identical to
   the pre-change value (`0.1165`) — proving the change is purely additive.
2. **Drift surfaced, never credited.** A record with `requested_model != resolved_model` shows
   `model_drift:true`, is bucketed by `resolved_model` in the scoreboard, and appears in the drift
   column — never counted toward the requested model's pass rate.
3. **First-try derivation correct.** The scoreboard computes `first-try%` as
   `sequence==first ∧ verdict==pass` over records; the sonnet-fail-then-opus-pass repair example
   produces two rows and credits neither model with an unearned first-try pass.
4. **Fail-open.** An `unavailable`/absent cost file still yields telemetry records (role/verdict/
   requested-model present; cost/resolved-model `null`, `cost_available:false`); no dispatch is
   blocked and no cost figure changes.
5. **Quarantine.** A `resolved_model` absent from `model-rates.json` (and the `<synthetic>` model)
   is excluded from pass-rate aggregation and reported on the scoreboard's `unattributed` line.
6. **Suites green.** `tests/test_policy_hooks.sh`, `tests/test_cost_hook.sh`,
   `tests/test_scoreboard.sh`, and `bash install.sh` all pass.

## Out of scope

Automatic routing-table edits (evidence only; the human edits `agents/orchestrator.md`); any live
HUD or web surface; per-token model benchmarking; pricing of server web-search/web-fetch (still
counted, not priced, per the cost design); the orchestrator's own session usage (still `/usage`);
cross-machine telemetry aggregation beyond ordinary git flow of `docs/telemetry/` to canonical main.
