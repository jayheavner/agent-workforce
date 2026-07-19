# Model-Tailored Plan Formatting — Implementation Plan (formatted for Claude Sonnet 5)

<plan_meta>
execution-contract: 1
target_build_model: claude-sonnet-5
formatting_note: This plan is written for a Sonnet 5 builder. Every task uses the same fixed template.
  Every step is one atomic action with one verb. Commands are literal — run them exactly as written.
  Sections are XML-delimited so you can parse each block unambiguously. Do only what a step says; do
  not infer additional work. When a step says "do not," that is a hard boundary, not a preference.
</plan_meta>

<how_to_execute>
1. Load the required sub-skill `superpowers:subagent-driven-development` (or `superpowers:executing-plans`).
2. Do the tasks in order: T1 → T2 → T3 → T4 → T5 → T6. Do not start Stage 2 (T7, T8).
3. For each task: read `<preflight>` and run every check in it BEFORE editing. Then do `<steps>` in
   number order. Then run every `<verify>` command and confirm the expected output. Then commit exactly
   the files in `<commit>`.
4. If a `<preflight>` check fails, or reality differs from what a step assumes, STOP and return the stop
   class named in that task's `<escalate>` block. Do not improvise a workaround.
5. Do not reformat, rename, or edit any file not named in the current task's `<files>` block.
</how_to_execute>

<goal>
Make the plan a builder receives legible to the model that will execute it: Claude builders get
XML-structured dispatch framing, GPT/Codex builders get Markdown-header framing, reasoning-tier upshifts
get outcome-first framing — WITHOUT the durable plan artifact ever becoming model-specific, and WITHOUT
shipping the "framing improves output" claim as an unmeasured fact.
</goal>

<architecture>
Two things are separated:
1. The durable plan artifact stays one canonical, model-neutral document, authored once. It is upgraded
   so each load-bearing contract block is an explicitly delimited, named block. It contains NO model
   reference.
2. The dispatch envelope the orchestrator wraps around the plan carries the model-appropriate framing.
   The orchestrator is the only actor holding both the chosen model and the finished plan at once, so
   framing lives there.

Framing = two composed axes, not one enum: notation(vendor) [XML for Claude, Markdown for GPT] ×
stance(tier) [outcome-first on a reasoning-tier upshift]. The envelope REFERENCES plan blocks by their
named delimiters and NEVER restates their content — so framing cannot contradict the plan and cannot
drift.
</architecture>

<staging>
Stage 1 (T1–T6): structural. Ships on engineering merit. Do these.
Stage 2 (T7–T8): the framing-content claim, gated on a measured baseline. Do NOT do these in this build.
</staging>

<tech_stack>
Markdown (agent/skill prose). Python 3 (extends scripts/render_codex_agents.py and
tests/test_codex_profiles.sh). Bash + jq (matches existing hooks/tests). No new runtime dependencies.
</tech_stack>

<global_constraints>
- Workspace: all edits occur in this checkout:
  /Users/jay/claude/ai-agent-team/.claude/worktrees/fifty-one-dollar-fixes . Do not edit any other checkout.
- No new dependencies. No package installs.
- Keep every file under ~300 lines. agents/orchestrator.md is already large — add only tight prose.
- Codex profiles under codex/agents/ are GENERATED. Never hand-edit them. Regenerate with the render
  script. After regenerating, `git diff` must be clean.
- Security: put no secret in any prose, framing string, or telemetry record. The telemetry framing field
  is a fixed enum, never free text.
</global_constraints>

<single_source_of_truth>
All framing RULES live in exactly one file: skills/agent-workforce/references/plan-formatting.md .
Every other site (orchestrator, builder, generated Codex profiles) POINTS AT it and does not restate the
rules. T5's test enforces this. If you catch yourself copying a framing rule into a second file, stop —
that is the exact thing this plan forbids.
</single_source_of_truth>

---

# STAGE 1 — structural (do T1 through T6)

<task id="T1-house-format">
<outcome>
Every new plan the planning skill produces renders its four load-bearing contract blocks as explicitly
delimited, individually-named blocks — not free prose. The house format contains NO model reference.
</outcome>

<files>
Modify: skills/planning/SKILL.md
Do not touch any other file in this task.
</files>

<preflight>
Run these before editing. Each must pass or STOP.
1. `test -f skills/planning/SKILL.md && echo OK` → expects `OK`.
2. `grep -nE "^## Tasks" skills/planning/SKILL.md || echo "why: expected the '## Tasks' section to edit"`
   → expects a line number (the fallback must NOT fire).
3. `grep -cE "^### " skills/planning/SKILL.md` → expects a count of at least 6 (the six task subsections).
</preflight>

<fixed_interfaces>
These are FIXED. Do not rename or reword them. Downstream tasks depend on these exact strings:
- Block name 1: `Interfaces and invariants`
- Block name 2: `Acceptance mapping`
- Block name 3: `Executable examples`
- Block name 4: `Escalation triggers`
INVARIANT (must hold): the house format contains no model / vendor / tier token (no "Sonnet", "Opus",
"GPT", "Claude", "XML"). This neutrality is the whole point of the seam.
</fixed_interfaces>

<steps>
1. In skills/planning/SKILL.md, in the "## Tasks" section, add a convention stating each of the four
   named blocks above is written as an explicitly delimited block a reader can extract unambiguously
   (a bounded block, not a prose paragraph under a heading).
2. Add one short subsection titled "Model-neutral by design" stating: the plan carries no model
   reference; per-model framing is applied by the orchestrator at dispatch time; see
   references/plan-formatting.md for the framing rationale.
3. In that subsection, point to references/plan-formatting.md. Do NOT restate any framing rule here.
</steps>

<discretion>
Allowed: exact wording of the convention and the new subsection; where inside "## Tasks" to place it.
NOT allowed: changing the four block names; introducing any model/vendor/tier token; restating framing
rules.
</discretion>

<verify>
Run all. Each must produce its expected output.
1. `grep -nE "Interfaces and invariants|Acceptance mapping|Executable examples|Escalation triggers" skills/planning/SKILL.md`
   → expects all four names present.
2. `grep -niE "sonnet|opus|gpt|claude|xml" skills/planning/SKILL.md || echo "why: house format must stay model-neutral — no model tokens expected"`
   → expects the fallback line to FIRE (i.e. no model tokens in the file).
3. Reviewer judges (judgment): the blocks are genuinely extractable, not relabeled prose. A "no" = a
   block that is still a prose paragraph with a heading.
</verify>

<escalate>
If preflight #2 fails (no "## Tasks" section) or a named block would collide with an existing contract →
return RESULT_STATUS: INCOMPLETE, STOP_CLASS: PLAN_DEFECT. Do not restructure the skill to force a fit.
</escalate>

<commit>
Files: skills/planning/SKILL.md
Subject: feat(planning): name plan contract blocks for model-neutral parsing
</commit>
</task>

---

<task id="T2-framing-reference">
<outcome>
One new file defines the entire framing regime as two composed axes and is the ONLY place the rules
exist. It includes three worked examples: a Claude XML envelope, a GPT Markdown envelope, and one
malformed envelope that must be rejected.
</outcome>

<files>
Create: skills/agent-workforce/references/plan-formatting.md
Do not touch any other file in this task.
</files>

<preflight>
1. `test -d skills/agent-workforce/references && echo OK` → expects `OK`.
2. `ls skills/agent-workforce/references/` → expects to see roles.md, model-policy.md,
   surface-compatibility.md (confirms this is the right directory).
3. `grep -niE "terra|sol|sonnet|opus" skills/agent-workforce/references/model-policy.md | head -5`
   → read the output; confirm the vendor/tier mapping (Sonnet/Opus = Claude; Terra/Sol = GPT) before
   you write it into the new file.
</preflight>

<fixed_interfaces>
These label strings are FIXED and reused by T3, T4, T6. Pick them here, use them verbatim everywhere:
- `claude-xml`   (notation for Claude family)
- `gpt-markdown` (notation for GPT family)
- `outcome-first` (stance for a reasoning-tier upshift)
- `unframed-fallback` (the safe default on an unrecognized family)
</fixed_interfaces>

<steps>
1. Create skills/agent-workforce/references/plan-formatting.md.
2. Write the two-axis model: notation(vendor) × stance(tier). State that they compose (a Claude
   reasoning upshift = claude-xml + outcome-first).
3. Write the family → notation table: Claude → XML tags `<task>`, `<plan_reference>`, `<in_scope_slice>`,
   `<terminal_result>`; GPT → Markdown headers of the SAME fields.
4. Write the tier → stance rule: a reasoning-tier upshift uses `outcome-first` — lead with outcome and
   invariants, de-emphasize prescriptive step ordering.
5. Write the rule: the envelope REFERENCES the plan's named blocks (from T1) by name and NEVER restates
   their content.
6. Write the safe-fallback invariant: an unrecognized or ambiguous vendor family → `unframed-fallback`
   (dispatch un-framed) PLUS a logged observable.
7. Add three worked Given/When/Then examples inside the file: (a) a correct Claude XML envelope, (b) a
   correct GPT Markdown envelope, (c) one malformed envelope and the statement that it MUST be rejected.
</steps>

<discretion>
Allowed: the prose; the exact XML/Markdown shown in the examples. NOT allowed: omitting either axis, the
fallback rule, the by-name-never-restate rule, or any of the three required examples; using label strings
other than the four fixed above.
</discretion>

<verify>
1. `grep -niE "notation|stance|vendor|tier" skills/agent-workforce/references/plan-formatting.md || echo "why: two-axis model must be present"`
   → expects matches (fallback does NOT fire).
2. `grep -niE "unframed-fallback|unrecognized" skills/agent-workforce/references/plan-formatting.md || echo "why: safe-fallback rule must be stated here"`
   → expects matches (fallback does NOT fire).
3. `grep -cE "Given|When|Then" skills/agent-workforce/references/plan-formatting.md` → expects at least 3
   (the three examples).
4. Reviewer judges (judgment): each framing outcome has a stable cite-able label so consumers can point
   at it rather than paraphrase. A "no" = rules only applicable by copying them into the orchestrator.
</verify>

<escalate>
If model-policy.md shows a model that is neither cleanly Claude nor GPT and you cannot map it to a
notation → apply `unframed-fallback` as the documented answer. Only if that is not acceptable, return
STOP_CLASS: PRODUCT_DECISION. Do not invent a third notation on your own.
</escalate>

<commit>
Files: skills/agent-workforce/references/plan-formatting.md
Subject: feat(agent-workforce): add single-source plan-formatting framing reference
</commit>
</task>

---

<task id="T3-orchestrator-framing">
<outcome>
At the point the orchestrator dispatches a builder, it selects framing by composing notation(vendor) ×
stance(tier) PER THE REFERENCE FILE, applies the safe fallback on an unrecognized family, and records
which framing it applied. It CITES the reference and does not restate the rules.
</outcome>

<files>
Modify: agents/orchestrator.md
Do not touch any other file in this task.
</files>

<preflight>
1. `grep -nE "^## Execution contracts and builder results" agents/orchestrator.md || echo "why: expected this section to edit"`
   → expects a line number (fallback must NOT fire).
2. `wc -l agents/orchestrator.md` → record the current line count. Your addition must stay a tight
   paragraph and keep the file well under 300 lines relative to its structure.
3. `test -f skills/agent-workforce/references/plan-formatting.md && echo OK` → expects `OK` (T2 done).
</preflight>

<fixed_interfaces>
Use the exact label strings T2 defined: claude-xml, gpt-markdown, outcome-first, unframed-fallback.
INVARIANT: the envelope references the plan's named blocks (T1) — it carries no restated plan content.
INVARIANT: framing is additive; an un-framed dispatch stays valid (backward compatible).
</fixed_interfaces>

<steps>
1. In the "## Execution contracts and builder results" section of agents/orchestrator.md, add ONE tight
   paragraph: when dispatching a builder, wrap the plan reference in the framing selected by
   notation(vendor of chosen model) × stance(tier), per references/plan-formatting.md.
2. In that same paragraph, state: on an unrecognized family, dispatch un-framed (unframed-fallback) and
   note it; record the applied framing label for telemetry (this feeds T4).
3. Cite references/plan-formatting.md by path. Do NOT copy its tables or rules into orchestrator.md.
</steps>

<discretion>
Allowed: placement and wording of the paragraph. NOT allowed: restating the reference's rules; omitting
the fallback; using labels other than T2's.
</discretion>

<verify>
1. `grep -nE "plan-formatting.md" agents/orchestrator.md || echo "why: orchestrator must cite the single source"`
   → expects the citation present (fallback does NOT fire).
2. `grep -niE "<task>|<plan_reference>|xml for claude|markdown for gpt" agents/orchestrator.md || echo "why: orchestrator must NOT restate framing rules — cite only"`
   → expects the fallback line to FIRE (no restated rules).
3. Reviewer judges (judgment): the paragraph composes both axes and states the fallback without pushing
   the file toward the line ceiling. A "no" = duplicated reference tables, or more than a tight paragraph
   added.
</verify>

<escalate>
If you cannot add the paragraph without materially restating the reference (because the section format
forces inline rules) → return STOP_CLASS: PLAN_DEFECT. The cite-don't-restate rule is load-bearing.
</escalate>

<commit>
Files: agents/orchestrator.md
Subject: feat(orchestrator): frame builder dispatches per plan-formatting reference
</commit>
</task>

---

<task id="T4-telemetry-field">
<outcome>
Every builder dispatch's telemetry record carries which framing was applied, so a future A/B is
falsifiable and a wrong-framing dispatch emits a signal instead of being invisible.
</outcome>

<files>
Modify: docs/telemetry/README.md
Modify (candidate — preflight confirms exact file): the telemetry-writing path and/or
tools/agent-team-scoreboard.sh
Modify (candidate): the closeout/telemetry instruction in agents/orchestrator.md so the scribe is given
the applied framing label to record.
Do not touch files outside this list.
</files>

<preflight>
1. `sed -n '1,60p' docs/telemetry/README.md` → read the v1 schema; confirm whether the schema is
   versioned and whether adding a field requires a version bump.
2. `test -f docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md && echo OK` → expects `OK`;
   read it to follow the schema-evolution convention.
3. `grep -rniE "schema.*1|logged_at|resolved_model" tools/ docs/telemetry/ | head` → identify the exact
   file that writes a telemetry record (this resolves the first candidate path).
</preflight>

<fixed_interfaces>
The `framing` enum values are EXACTLY: claude-xml, gpt-markdown, outcome-first, unframed-fallback, n/a.
(`n/a` for non-builder roles.) Any other value is invalid.
INVARIANT: telemetry stays best-effort and never a gate. A missing framing field degrades to n/a/unknown;
it never blocks closeout.
</fixed_interfaces>

<steps>
1. Add a `framing` field to the telemetry schema in docs/telemetry/README.md, with the enum above. If the
   spec (preflight #2) requires a version bump to add a field, follow that convention exactly.
2. In the file that writes telemetry records (from preflight #3), ensure the framing label the
   orchestrator recorded (T3) is written into the record. Change only what is needed.
3. If agents/orchestrator.md's closeout/telemetry instruction must pass the framing label to the scribe,
   add that one instruction. Keep it tight.
4. Validate any script you touched: `python3 -m py_compile <file>` for Python, `bash -n <file>` for shell
   → each expects exit 0.
</steps>

<discretion>
Allowed: whether this is a v1 field-add or a v2 bump (per the spec); internal tooling structure. NOT
allowed: an enum that differs from T2; making telemetry a gate.
</discretion>

<verify>
1. `grep -nE "\"framing\"" docs/telemetry/README.md || echo "why: telemetry schema must document the framing field"`
   → expects the field documented (fallback does NOT fire).
2. `bash tools/agent-team-scoreboard.sh <fixture.jsonl> 2>&1 | grep -iE "framing" || echo "why: scoreboard must surface the framing field, not error on it"`
   where <fixture.jsonl> is a telemetry line carrying a framing value → expects the field surfaced.
3. For every script touched: `python3 -m py_compile <file>` or `bash -n <file>` → expects exit 0.
</verify>

<escalate>
If the telemetry spec forbids adding a field without a formal schema-version process beyond this plan's
scope → return STOP_CLASS: PLAN_DEFECT (needs a spec amendment). Do not bypass the schema discipline.
</escalate>

<commit>
Files: docs/telemetry/README.md plus the minimal tooling / orchestrator edits actually made
Subject: feat(telemetry): record applied dispatch framing for A/B observability
</commit>
</task>

---

<task id="T5-drift-test">
<outcome>
A test fails at build time if framing rules drift between the reference file, the orchestrator's
citation, the builder's citation, and the regenerated Codex profiles.
</outcome>

<files>
Create: tests/test_plan_formatting_drift.sh   (OR extend tests/test_codex_profiles.sh if preflight shows
that is the established home)
Modify (candidate): scripts/render_codex_agents.py — ONLY if the builder's framing-citation line would
not otherwise survive rendering.
Do not touch files outside this list.
</files>

<preflight>
1. `sed -n '1,40p' tests/test_codex_profiles.sh` → read the house test style; match it.
2. `sed -n '20,25p' scripts/render_codex_agents.py` → confirm role_body copies the role's body verbatim
   (it splits frontmatter and takes part 3), so a citation line in agents/builder.md will propagate.
3. `ls tests/` → confirm how tests are named/run so your new test fits the convention.
</preflight>

<steps>
1. Create the drift test. It must assert ALL of:
   (a) the framing-rule vocabulary appears ONLY in plan-formatting.md, not restated in orchestrator.md or
       builder.md;
   (b) agents/orchestrator.md contains the citation to references/plan-formatting.md;
   (c) agents/builder.md contains the citation, and it survives Codex rendering.
2. Make the test exit non-zero (with a message naming the duplication) when a framing rule is restated in
   a consumer file; exit 0 otherwise.
3. Prove the red: temporarily copy a framing rule verbatim into agents/orchestrator.md, run the test,
   confirm it fails naming the duplication, then REVERT the injection.
4. Regenerate Codex profiles: `python3 scripts/render_codex_agents.py`. Confirm no diff.
</steps>

<discretion>
Allowed: test language/structure within house conventions; new test file vs extending the codex test.
NOT allowed: a test that does not actually catch an injected duplication; leaving the render diff dirty.
</discretion>

<verify>
1. `bash tests/test_plan_formatting_drift.sh; echo "exit=$?"` → expects `exit=0` on the clean tree.
2. Red demo (same command) after injecting a restated rule into agents/orchestrator.md → expects a
   NON-zero exit naming the duplication; then revert and re-run to confirm `exit=0`.
3. `python3 scripts/render_codex_agents.py && git diff --exit-code codex/ || echo "why: rendered profiles must match checked-in; regenerate, do not hand-edit"`
   → expects a clean diff (fallback does NOT fire).
</verify>

<escalate>
If the builder citation cannot survive rendering without a render-script change that touches OTHER roles
→ return STOP_CLASS: PLAN_DEFECT (broad blast radius needs an amendment). Do not silently widen scope.
</escalate>

<commit>
Files: tests/test_plan_formatting_drift.sh (+ candidate render tweak if made)
Subject: test(agent-workforce): enforce single-source plan-formatting across surfaces
</commit>
</task>

---

<task id="T6-builder-line">
<outcome>
The builder treats dispatch framing as priming only; the plan file and its named blocks remain the
authoritative contract. On any conflict, the plan governs.
</outcome>

<files>
Modify: agents/builder.md
Regenerate (do not hand-edit): codex/agents/agent_workforce_builder*.toml via the render script.
Do not touch files outside this list.
</files>

<preflight>
1. `grep -nE "^## Contract consumption" agents/builder.md || echo "why: expected this section to edit"`
   → expects a line number (fallback must NOT fire).
2. `test -f skills/agent-workforce/references/plan-formatting.md && echo OK` → expects `OK`.
</preflight>

<fixed_interfaces>
INVARIANT: plan governs over framing on any conflict. This is the safety backstop that keeps a
misclassification's blast radius at "degraded to un-framed", never "corrupted output".
</fixed_interfaces>

<steps>
1. In the "## Contract consumption" section of agents/builder.md, add ONE tight sentence: the dispatch
   may arrive in model-appropriate framing that primes reading order and emphasis; the plan file and its
   named blocks remain authoritative; on any conflict, the plan governs.
2. Cite references/plan-formatting.md. Do NOT restate framing rules (T5 will fail if you do).
3. Regenerate the builder Codex profile: `python3 scripts/render_codex_agents.py`.
</steps>

<discretion>
Allowed: exact sentence wording; placement within Contract consumption. NOT allowed: wording that lets
outcome-first stance excuse skipping an ordered plan step; restating rules; hand-editing the .toml.
</discretion>

<verify>
1. `grep -niE "framing|plan-formatting.md" agents/builder.md || echo "why: builder must acknowledge framing and cite the reference"`
   → expects both present (fallback does NOT fire).
2. `python3 scripts/render_codex_agents.py && git diff --exit-code codex/agents/agent_workforce_builder.toml || echo "why: builder profile must be regenerated to include the line"`
   → after regeneration the profile carries the line; there must be no UN-regenerated (manual) diff.
3. Reviewer judges (judgment): the line closes the framing-vs-plan conflict without weakening plan
   authority. A "no" = wording that lets stance override an ordered plan step.
</verify>

<escalate>
If the render produces a diff in any NON-builder profile → return STOP_CLASS: PLAN_DEFECT (unexpected
blast radius).
</escalate>

<commit>
Files: agents/builder.md + regenerated codex/agents/agent_workforce_builder*.toml
Subject: feat(builder): framing primes, plan governs on conflict
</commit>
</task>

---

# STAGE 2 — GATED. DO NOT EXECUTE IN THIS BUILD.

<stage2_gate>
Stage 2 (T7, T8) is entered ONLY after Stage 1 has run in production long enough to produce a baseline,
and a human reads the baseline and decides to proceed. As the builder, DO NOT do T7 or T8. They are
recorded here for completeness only.
</stage2_gate>

<task id="T7-baseline" status="gated-do-not-run">
<outcome>
A documented baseline of builder first-try-pass rate by model family from existing telemetry, plus an
explicit finding on whether the telemetry verdict bit is sensitive enough to detect a formatting effect.
</outcome>
<verify>
- (mechanical) `bash tools/agent-team-scoreboard.sh 2>&1 | grep -iE "resolved_model|first.?try|pass" || echo "why: scoreboard must emit first-try-pass by model, or the baseline doc must record insufficient-data with N records"`
  → expects grouped baseline figures, OR a baseline doc stating `insufficient data — N records` with a real N.
- (judgment, human) a stated verdict on measurement sensitivity. A "no" = proceeding to T8 on too few
  records or a verdict bit that cannot separate "framing helped" from "task was easy".
</verify>
<escalate>
Insufficient telemetry volume, or a finding that the verdict bit can't detect the effect → STOP_CLASS:
PRODUCT_DECISION to the human (enrich telemetry / ship on published-guidance basis / stop). Never proceed
silently.
</escalate>
</task>

<task id="T8-content-tuning" status="gated-do-not-run">
<outcome>
Gated behind T7's human decision. If T7 shows a signal: A/B the framing labels using T4's framing field
as the split variable, tune the reference's framing content toward the measured winner. If T7 shows no
usable signal: document that framing ships on a published-guidance basis, effect unmeasured. The
architect writes T8's detail as an amendment once T7 returns.
</outcome>
</task>

---

<self_review>
Coverage: every Stage-1 task maps to a panel recommendation — house-format (T1), two-axis single-source
reference with required examples (T2), orchestrator cite-don't-restate + fallback (T3), telemetry
observability (T4), drift test with teeth (T5), framing-primes-plan-governs (T6). Stage 2 carries the
measurement gate (T7/T8).
Placeholder scan: no TBD/TODO. Candidate paths in T4/T5 are labeled for preflight, not guessed. T8 is
deliberately scoped-not-detailed because it is gated on T7 data.
Consistency: the four block names are fixed in T1 and consumed by T2/T3/T5; the framing labels are fixed
in T2 and reused by T3/T4/T6.
Builder feasibility: paths verified present at plan time except the labeled candidates; commands are
literal; render_codex_agents.py's verbatim-body-copy was confirmed so the T6 citation propagates.
Verifier observability: every mechanical check is a literal command with expected output and a `|| echo`
reason on silent-failure greps; every judgment check names a judge and a real "no".
</self_review>

<acceptance_criteria_index>
This plan states its acceptance checks inline per task under <verify>. The formal falsifiable list
(AC-1..AC-14) is preserved verbatim in the model-neutral sibling plan
docs/superpowers/plans/2026-07-18-model-tailored-plan-formatting.md and passes tools/lint_acceptance_checks.py.
This Sonnet-formatted file restates those same checks as literal per-task <verify> commands for direct
execution.
</acceptance_criteria_index>
