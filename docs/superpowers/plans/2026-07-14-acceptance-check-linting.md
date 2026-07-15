# Acceptance-Check Linting — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-07-13-acceptance-check-linting-design.md`
(Approved 2026-07-14; Decision 6 resolved: Python 3 stdlib).

Execution note: worked to completion in one session at the human's direction; tasks are
recorded checked in the order the work ran. All code tasks red-first.

## Tasks

- [x] **T1 — RED: `tests/test_acceptance_lint.sh` + fixtures.** Bash, repo convention
  (PASS/FAIL counters, exit 0 iff FAIL=0), driving the tool over
  `tests/fixtures/acceptance-lint/*.md` plan snippets. Asserts, per spec §5: pure-echo
  check → `BLOCK tautological-check` + non-zero exit; `grep -q` / `diff -q` / bare
  `test -f` with no failure branch → `BLOCK silent-check`; the same three WITH
  `|| echo "why…"` → no finding and exit 0 (the false-positive guard — the dangerous
  direction for a blocking lint); `(mechanical)` with no `Check:` →
  `BLOCK mechanical-criterion-without-check`; `(judgment)` with no `Bar:` →
  `WARN empty-judgment-criterion` and exit 0 (advisory never blocks); unfalsifiable
  phrasing → `WARN unfalsifiable-phrasing`; observable-token judgment criterion →
  `WARN mislabeled-criterion`; a clean plan → zero findings, exit 0. Red: tool absent.
- [x] **T2 — GREEN: `tools/lint_acceptance_checks.py`.** Python 3 stdlib (`re`, `shlex`).
  Parses `- [ ] AC-N (mechanical|judgment): …` criterion blocks (inline or indented
  continuation lines) with `Check:`/`Judge:`/`Bar:` clauses. Segments each check on
  `&&`/`||`/`;`/`|`, shlex-tokenizes each segment. Emits
  `BLOCK|WARN <class> <AC-id> — why: … good: …` per finding; exits non-zero iff any
  BLOCK fired. Untagged plans (no parseable criteria) exit 0 — the lint governs the
  declared shape, it does not retroactively fail legacy plans.
- [x] **T3 — Agent instruction text** (spec §1, §2, §6 size audit): architect gains the
  criterion shape + self-lint discipline (~14 lines); reviewer gains plan-critique mode
  (~10 lines) parallel to spec-critique; orchestrator gains the plan-gate dispatch line.
  The two-questions block is untouched (drift-test protected).
- [x] **T4 — Codex profiles re-rendered** (`scripts/render_codex_agents.py`) — the agent
  text edits otherwise leave generated profiles stale (learned from the telemetry merge).
- [x] **T5 — Verification gate.** All 13 suites green (12 existing + the new
  test_acceptance_lint.sh, picked up by the repo's `tests/test_*.sh` convention);
  `install.sh` untouched per spec non-goal.
- [x] **T6 — Commit + push** in logical units.
