# Handoff — Autonomy-First Redesign (2026-07-19)

**State:** shipped, pushed, installed. `main` = `6df2ddc` on `origin/main`, working tree clean,
all 18 test suites green, both profiles (`~/.claude`, `~/.claude-jay`) installed and
`install.sh --check` clean. **Not yet done: a live shakedown task through the new orchestrator.**

This report records what was changed, why, and every decision made on the owner's behalf, so a
fresh session can continue the conversation without re-deriving anything. The companion design
spec is `docs/superpowers/specs/2026-07-18-autonomy-first-redesign.md`.

---

## 1. The assignment

Owner directive, paraphrased: the agent team eventually delivers but takes forever, asks too
many stupid questions, and never closes out properly — the required end-of-task pricing only
appears after prompting, and then as an estimate. Requirement: a workforce that can be turned
loose on any problem and deliver quickly and cost-effectively; bespoke agents with set models,
efforts, and permission boundaries; heavy use of the related skills repo; self-growing (create
new skills/agents when it meets a novel problem). Full latitude, no clarifying questions.

## 2. Diagnosis (evidence-backed)

Three parallel analyses (the csv2json transcript + postmortems + $51-session plan; the
enforcement machinery; the skills repo) plus live inspection of both profiles converged on:

1. **Fixes never reached production.** Both profiles were frozen at the July-13 build
   (commit 9df4727) — ~31 commits behind. The closeout Stop hook file did not exist in
   `~/.claude/hooks`; `~/.claude-jay` had no hooks at all; `debugger.md`/`executor.md` were
   never installed; three retired policy hooks lingered. Every incident's fix was merged and
   never installed, because install was a manual, terminal, auth-blocked step that also held
   the closeout hook hostage to ~21 unrelated test suites and org-skill validations.
2. **Process weight was constant, not proportional.** The "Small" route was 6+ dispatches by
   contract; a trivial CSV→JSON tool consumed 11 dispatches, 2 approval gates, 4 scribe status
   notes, ~45 minutes, ~$3 + orchestrator usage. The orchestrator had no shell, so every fact
   crossed a paid dispatch boundary.
3. **Behavior lived in prose that grew with every failure.** `agents/orchestrator.md` reached
   475 lines / ~9,300 words (charters, WORKFORCE_* marker economy, execution-contract
   envelopes, two-questions doctrine, decision inventories, spec-critic pipeline, telemetry
   choreography). Sessions violated rules while quoting them. Only hooks ever changed behavior.
4. **Closeout failed at both ends.** Live: unenforced (hook absent). At HEAD: the cost report
   only fired at a "final gate" decayed sessions never reached, a blended-estimate fallback
   still existed in the installed build, and every "exact" report excluded the orchestrator's
   own session usage — usually the largest line. When enforcement did run (July 17), it fired
   mid-task while dispatches were in flight and demanded a receipt schema it couldn't verify:
   67 rote receipts, 19 blocks, compliance theater.
5. **The question pattern was specific:** (a) preference questions already answered
   ("recommend approve as-is"), (b) fact questions a lookup could resolve, (c) approval
   questions standing authorization already covered.
6. **Self-improvement loops never produced data.** Zero gap records, zero valid telemetry
   records — both depended on model memory at end-of-session and nothing blocked on absence.

Mechanics verified against current Claude Code docs before designing: plugin-shipped agents
ignore `hooks`, `permissionMode`, and `mcpServers` frontmatter (so live plugin mode loses
per-role enforcement and no-prompt autonomy); Stop hooks can block with a reason the model
sees; per-dispatch `model` override works; there is no per-dispatch `effort` override.

## 3. Design principles applied

- **Mechanism over prose.** Anything that must happen every time is a hook or script; prose is
  reserved for judgment and kept short enough to hold.
- **Process proportional to the task, floor of one dispatch.**
- **Facts are free** — the orchestrator gets a read-only shell.
- **Four gate conditions are the entire question policy;** everything else is
  decide-and-disclose.
- **The cost report is computed, not remembered.**
- **The launcher is the deployment** — staleness self-heals at launch.
- **Create → use → disclose** replaces record-and-wait for capability gaps.

## 4. What changed (by file)

### Contracts (`agents/`)
- `orchestrator.md`: 476 → ~150 lines. Route table with floor-of-one; read-only Bash for
  observation (secrets + audit hooks wired); four-gate question policy; "Growing the team"
  section; closeout = verify → commit (executor) → one scribe note → final message with the
  computed cost table. Standing authorization and consume-once kept from the July-15
  amendments (they were correct — just buried).
- `architect.md`: decision-inventory/two-questions/execution-contract machinery removed; keeps
  investigate-first, falsifiable acceptance criteria (compact), dissolve-binaries,
  amendments-as-deltas; gains skill/agent drafting duty under `growing-the-team`.
- `builder.md`: RESULT_ID/SUPERSEDES envelope and typed-stop taxonomy removed. Two dispatch
  shapes (from a plan; direct build with a stated micro-plan). TDD loop, preflight reality
  check, plain typed blocker reporting.
- `verifier.md`: delivery-contract/linter/WORKFORCE_VERIFICATION marker removed; evidence
  rules, UNCHECKED-with-reason, page-facing + full-page-screenshot rules kept.
- `reviewer.md`: process-audit mode and two-questions block removed; code review + plan
  critique (still runs `tools/lint_acceptance_checks.py`) + spec critique on request.
- `scribe.md`: telemetry duty and per-builder-dispatch cadence removed; one closeout note, or
  a handoff note on request.
- `debugger`, `executor`, `researcher`, `deployer`, `ops`, `ticketer`: unchanged (already lean).

### Enforcement (`hooks/`, `bin/`)
- **NEW `hooks/cost_report.py`** (+ `bin/agent-workforce-cost-report` wrapper): prices the
  ENTIRE session — main-session transcript + every subagent transcript — at list rates from
  `model-rates.json`, dedup by message id, intro-pricing by date, per-agent attribution,
  unpriced models reported as exact token counts (no estimate path). Also emits mechanical
  telemetry JSONL (`--telemetry-dir`).
- **`hooks/agent_team_closeout.py` rewritten** (500 → ~215 lines): Stop hook only. Allows
  when no dispatches ran or dispatches are in flight; blocks (max 3 per session, then
  fail-open with a stderr warning — never wedges) when the final message lacks `## Cost
  report`, supplying the computed table in the block reason; requires dirty-tree
  acknowledgment when git-mutating roles ran; writes telemetry on a passing stop; state file
  cleaned up. No receipt schema, no ledger fields, no ownership claims, no SubagentStop
  marker enforcement.
- `hooks/agent-team-dispatch-guard.sh`: researcher shell-verb regex removed (high
  false-positive); keeps subagent_type validation, git-mutation serialization
  (`PARALLEL_SAFE` marker), and the every-10th-dispatch budget ratchet.
- `hooks/hooks.json` + `agent-team-plugin-router.sh`: reduced to
  secrets/dispatch/audit/cost/closeout-stop.
- `hooks/model-rates.json`: added opus-4-7, opus-4-6, sonnet-4-6, sonnet-4-5 families so
  overridden dispatches always price; `as_of` bumped. Current families verified against list
  prices (fable $10/$50, opus-4-8 $5/$25, sonnet-5 $3/$15 w/ intro $2/$10 → 2026-08-31,
  haiku $1/$5; cache ×1.25/×2/×0.1).
- **DELETED:** `hooks/process_assurance.py`, `hooks/agent-team-process-assurance.py`,
  `bin/agent-workforce-process-assurance`, `tools/lint_completion_claims.py`,
  `skills/process-auditing/`, `docs/process-assurance-operations.md`, and their five test
  suites. Net −8,022 lines. Rationale: defaulted OFF, never qualified, consumed more contract
  than any feature; the linter's receipt schema was gameable shape-checking. Recoverable from
  git history if ever wanted.

### Deployment (`bin/agent-workforce`, `install.sh`)
- Launcher rewritten: snapshot mode primary; sha-compares the profile manifest against the
  checkout and auto-installs on staleness (`AGENT_TEAM_SKIP_INSTALL_TEST=1` for speed), then
  `exec claude --agent orchestrator`. `--plugin` keeps legacy live mode; `--no-install` skips.
  Refuses to launch stale if the install fails.
- `install.sh`: validates only what it installs (hook syntax, frontmatter, skill resolution,
  the 8 focused hook suites — down from ~21); no longer blocks on unrelated org skills;
  process-assurance files moved to `RETIRED_HOOK_FILES` (purged on install; `--check` flags
  them); manifest/backup/rollback/`--check` machinery kept; `SKILLS-FRAMEWORK` revision parse
  relaxed to first-token.

### Skills
- **NEW `skills/growing-the-team/`**: the self-growth loop — create → use → disclose; drafts
  marked `provenance: provisional`; agents only for confirmed role gaps; rejected drafts
  deleted with the reason recorded.
- `skills/closeout/` rewritten to the five-phase ending (verify, commit, record, report
  honestly, price exactly).
- Re-vendored from `jayheavner/skills` @ `fe76667`: `reviewing` (gains the receiving-review
  chair — the one place this repo was strictly stale), `planning`, `handing-off`, `verifying`,
  `finishing-a-branch` (drops the local contract-machinery forks). `SKILLS-FRAMEWORK` updated;
  documents the two deliberate local forks kept (`convene-panel`, `auditing-requirements`
  patterns — both upstream candidates).
- `skills/agent-workforce/` (Codex orchestration): process-assurance section deleted, route
  table leaned, gap section now points at `growing-the-team`; `references/model-policy.md`
  spec-critic rows removed; `references/roles.md` de-referenced from retired machinery.

### Telemetry, docs, Codex
- `docs/telemetry/README.md` + `tools/agent-team-scoreboard.sh` + test rewritten for the
  mechanical schema (agent_id, role, resolved_models[], requests, tokens, cost_usd,
  session_id) written by the Stop hook. `docs/gaps/README.md` gained a pointer to
  `growing-the-team`.
- `README.md` rewritten (~550 → ~200 lines) around quick start, roster, routes, enforcement
  table, growing the team, shakedown.
- Codex: 26 profiles regenerated by `scripts/render_codex_agents.py` from the new contracts;
  `bin/agent-workforce-dispatch` and `install-codex.sh` stripped of process-assurance wiring.
- Plugin version bumped to 2.0.0.

### Tests (18 suites, all green)
- Deleted: `test_execution_handoff_text.sh`, `test_decision_discipline_drift.sh` (+5
  process-assurance/linter suites).
- New: `test_cost_report.sh` (17 checks); `test_agent_team_closeout.py` rewritten (9
  subprocess scenarios incl. in-flight allow, block-with-table, block cap, dirty-tree
  honesty; 85% coverage, gate at 80).
- Rewritten to pin the new contracts: `test_orchestrator_autonomy.sh`, `test_gap_loop_text.sh`,
  `test_closeout_audit.sh` (prose pins), `test_plugin_mode.sh` (new launcher + hooks.json),
  `test_agent_frontmatter.sh`, `test_dispatch_guard.sh`, `test_scoreboard.sh`.

## 5. Verification evidence

- `bash tests/test_*.sh`: 18/18 PASS (including Codex packaging against regenerated profiles).
- `install.sh --profile ~/.claude` (full validation) and `--profile ~/.claude-jay`: OK;
  both `--check` clean at build `6df2ddc`; retired hooks purged from `~/.claude/hooks`.
- `git push origin main` succeeded — the gh/Keychain auth failure from the July-17 status
  notes did not reproduce.
- `cost_report.py` exercised against fixtures AND this live session (it priced the redesign
  session itself: $96.42 total, $68.86 of it main-session — demonstrating exactly why
  excluding orchestrator usage was a lie of omission).
- Closeout hook exercised manually: block path returned the computed table verbatim.
- The new launcher's auto-install path was exercised for real (a test's first failing run
  triggered it against `~/.claude-jay` — backup at
  `~/.claude-jay/backups/agent-team-20260718-235106`; the test now uses a throwaway profile).

## 6. Decisions made on the owner's behalf (disclosed, reversible)

1. **Deleted process assurance wholesale** rather than leaving it dormant. Git history keeps it.
2. **Snapshot-primary, plugin-legacy** — driven by the documented plugin limitation
   (permissionMode ignored → permission prompts everywhere in live mode).
3. **Orchestrator got read-only Bash** — breaks the old "no shell on purpose" purity in favor
   of killing the dispatch-per-fact tax; mutation still forbidden by contract and audited.
4. **Dropped the receipt/ledger schema entirely** — the hook now enforces only what it can
   verify (cost table presence, dirty-tree acknowledgment).
5. **Re-vendored five skills over local forks** — the forks carried machinery being deleted;
   two genuinely-better local forks kept and documented.
6. **Budget ratchet, serialization guard, dispatch-type guard kept** — they're cheap and each
   traces to a real, expensive failure.
7. **Researcher dispatch-guard regex removed** — false-positive-prone; the orchestrator's own
   shell removes the misrouting temptation.
8. **Historical docs (STATUS-*, old specs, postmortems) left untouched** — they are the record.
9. **Fail-open block cap (3) on the closeout hook** — a hook must never wedge a session; a
   capped bypass is visible on stderr.

## 7. Landmines and open items for the next session

1. **No live shakedown yet.** The new orchestrator has not run a real task end-to-end. First
   thing to do: `./bin/agent-workforce` + the disposable csv2json-2 task from README
   §Shakedown. Watch: triage says builder → verifier (architect would be over-routing), no
   permission prompts, final message ends with the cost table including a main-session row.
2. **Stop-hook cadence in interactive sessions:** any turn-end after dispatched work with no
   dispatches in flight demands the cost table — so mid-conversation wrap-ups will carry
   running cost tables. Judged a feature (running spend visibility). If it annoys, the fix is
   one condition in `hooks/agent_team_closeout.py` (e.g. only enforce when the last message
   also claims completion), not a redesign.
3. **Codex surface regenerated but not live-tested** (`install-codex.sh` not run this session;
   `agent_workforce_spec_critic` profile still exists in `codex/model-policy.json` — harmless,
   maps to the reviewer's on-request critique mode; remove if unwanted).
4. **Upstream candidates for `jayheavner/skills`:** `growing-the-team`, the genericized
   `closeout`, the `convene-panel` and `auditing-requirements` forks. The org repo also has no
   tag since v0.1.0 — the pin is a raw SHA.
5. **`PARKING-LOT.md` not groomed** — some entries reference deleted machinery.
6. **Old per-profile cost logs / state:** `~/.claude/logs/agent-team-cost` holds pre-redesign
   session files; `~/.claude/state/agent-workforce-closeout` may hold stale pre-redesign state
   files (harmless; new hook ignores them, cleans its own on passing stops).
7. **Machine side effect:** the test agent ran `pip install --user coverage` (7.15.2) — needed
   by the closeout coverage gate then and now.
8. **Effort has no per-dispatch override** (confirmed against docs) — depth is steered by
   model tier + dispatch scope only. Frontmatter pins are the only effort control.
9. **`hooks/agent-team-budgets.json`** still sets the ratchet at 10 dispatches — tune there.
10. **Cost-file concurrency limitation remains:** two orchestrator sessions in one cwd share
    the cost-file glob; most-recent wins (documented, accepted).

## 8. Session cost (the tool's own output, list rates, main session included)

| Model | Input | Output | Cache write | Cache read | Cost |
|---|---:|---:|---:|---:|---:|
| claude-fable-5 | 6,749 | 243,151 | 1,464,545 | 60,902,028 | $96.22 |
| claude-haiku-4-5 | 14,360 | 6,869 | 89,193 | 377,218 | $0.20 |
| **Total** | | | | | **$96.42** |

Attribution: main session $68.86; six subagents $27.55 (failure-evidence $3.26, machinery
$10.18, skills-repo $2.40, docs-mechanics $0.20, test-suite $8.49, telemetry/scoreboard $3.02).
Figures as of report time; the final turns of the session add marginally to the main-session line.
