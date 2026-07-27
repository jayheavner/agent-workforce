# Dead-orchestrator reconcile — spec + plan (issue #8)

**Goal.** When an orchestrator dies mid-closeout (headless `claude -p` exits 0 on
"Connection closed mid-response" after deliverables land but before the cost
table prints, and a killed process fires no Stop hook), the death must stop being
silent — surface a `reconcile:` warning at the **next** session start.

**Architecture.** One new function `reconcile_lines(payload)` added to the
existing `hooks/session_start.py` pipeline. It reuses `scan_transcript` and
`COST_MARKER` from `hooks/agent_team_closeout.py` (imported the same way
`debug_run_archiver.py` already imports from that module — `sys.path.insert(0,
HERE)`), discovers the single most-recent prior `*.jsonl` transcript in the
current session's transcript directory, and applies one predicate. No new files,
no new infrastructure, no new dependencies.

**Tech stack.** Python 3 stdlib only (`json`, `os`, `subprocess`, `sys`) plus the
first-party sibling module `agent_team_closeout`. Tests: `unittest`, extending
`tests/test_session_start.py`.

## Global constraints (from project policy + the dispatch, verbatim where quoted)

- **Work tier:** small / contained single-hook change (stated in the dispatch).
  Per `policy:build-policy > coverage`: "trivial/small-tier work requires TDD
  (test-first at agreed seams) but no numeric threshold." Source: project-policy
  skill (`~/.claude/skills/project-policy`). TDD is mandatory here; no coverage
  percentage gate applies.
- **Workspace isolation (`policy:workspace-isolation`), resolved value quoted:**
  "the project checkout or worktree selected when the orchestrator session
  starts is the task workspace. Builder, verifier, reviewer, and deployer use
  that same explicit path for the full route; do not create a nested worktree
  from inside a specialist dispatch." Source: **project policy** (project-policy
  skill). Resolved workspace: the existing checkout at
  `/Users/jay/claude/agent-workforce`. Do **not** create a nested worktree.
- **Dependency freshness (`policy:dependency-freshness`):** resolved value —
  "versions verified current by web search … and pinned exactly." Source:
  project policy. **N/A for this task: zero new dependencies are added** (stdlib
  + the existing `agent_team_closeout` import), so there is no version to pin.
  This is itself an acceptance criterion below.
- **House rules (from the issue, binding):** the hook fails open and NEVER wedges
  or blocks a session start — exit 0 always, every path try/excepted. Read-only
  toward the project tree. `reconcile_lines` is wired into `main()` inside its own
  `try/except Exception: pass`, exactly like every existing pipeline step.

## Mutation scope (authorization legibility)

- **Modify:** `hooks/session_start.py` (add `HERE`, `PAUSE_MARKER`,
  `reconcile_lines`, one pipeline call).
- **Modify (tests):** `tests/test_session_start.py` (add helpers + new test
  methods).
- **Modify (docs):** `docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md`
  — append one dated bullet to the "Designed limitations" section.
- **Dependencies installed:** none.
- **Files created/moved/deleted:** none (tests create fixtures in their own
  `tempfile.TemporaryDirectory`, cleaned up).
- **State touched outside the repo:** `reconcile_lines` performs a **read-only**
  `os.listdir` + `os.path.getmtime` + `open(...)` on the session's transcript
  directory (e.g. under `~/.claude*/projects/...`), which lives outside the repo.
  It writes nothing anywhere.

## Security pass (pre-implementation)

- No secrets in code or logs. The warning surfaces only the prior transcript's
  **basename and path** plus generic guidance — never transcript *contents*, so
  no dispatched-work text (which could contain secrets) is echoed into
  `additionalContext`.
- Inputs validated at the boundary: `payload` is `isinstance`-checked;
  `transcript_path` is type/emptiness-checked; the directory is `isdir`-checked;
  each `getmtime`/parse is try/excepted. `scan_transcript` already opens with
  `errors="replace"` and skips unparseable lines.
- Errors sanitized: there is no error display path — every failure returns `[]`.

---

# Spec

## Detection predicate (in terms of `scan_transcript` outputs)

`scan_transcript(path)` returns `(total, in_flight, roles, order, last_text)`.
The prior session triggers the warning **iff all three hold**:

1. `total > 0` — specialist dispatches happened (Agent tool_use blocks were
   counted). Equivalent to `roles` non-empty; `total > 0` is used directly.
2. `COST_MARKER not in last_text` — the final human-visible message did **not**
   reach a normal closeout. `COST_MARKER == "## Cost report"`, imported from
   `agent_team_closeout`.
3. `PAUSE_MARKER not in last_text` — the session was **not** intentionally
   paused. `PAUSE_MARKER == "WORKFORCE_PAUSE: HUMAN_DECISION"`.

`last_text` is exactly what `scan_transcript` defines: every assistant text
record since the most recent `user` record, concatenated — so a truncated final
message (and even an `isApiErrorMessage` assistant record) is included, and
neither marker being present is the death signature.

## How the prior session is discovered

- The SessionStart payload's `transcript_path` is the **current** session's
  transcript. Prior sessions for the same project are sibling `*.jsonl` files in
  the same directory (verified: this is how the harness lays out per-project
  transcripts; `agent_team_closeout` reads exactly this path).
- Discovery inspects **only the single most-recent prior** `*.jsonl` (highest
  mtime), **excluding the current transcript by absolute path**.
- **Why only one, and why that is not nagging (design decision).** Checking the
  single most-recent prior catches the death at the moment it matters most — the
  very next start after the process died, when the dead transcript *is* the
  most-recent prior. It is bounded to one extra `scan_transcript` per start, and
  it self-clears: once any newer session exists (a clean closeout, a pause, or a
  plain chat), the most-recent prior is no longer the dead one and the warning
  stops. The cost of this simplicity is a **masking** trade — a plain later
  session started before anyone reconciles will hide an older dead one. That is
  the accepted, stated trade: it is strictly better than a warning that re-fires
  on every start of every unrelated future session forever (the false-positive
  cost the issue calls out). Detection is deferred to the next start by
  construction; it is a safety net, not real-time.

## Exact warning line the operator sees

A single `additionalContext` line (list entry), with `{name}` = prior basename
and `{path}` = prior absolute path:

```
reconcile: prior session {name} dispatched specialists but ended without a closeout cost report or a WORKFORCE_PAUSE. It may have died mid-closeout (e.g. a headless run whose connection dropped after deliverables committed but before the cost table printed), been interrupted/closed by the operator, or been allowed to stop at the enforcement cap. Committed deliverables are unaffected; the final report/telemetry for this session may be missing. Inspect {path} — recover the numbers with `bin/agent-workforce-cost-report --transcript {path}`.
```

**Revision (2026-07-26, plan-critique SHIP-WITH-FIXES).** The predicate
(`total>0 AND COST_MARKER not in last_text AND PAUSE_MARKER not in
last_text`) is also satisfied by three states that are NOT a mid-closeout
death: the enforcement-cap allow (`agent_team_closeout.py:420–424` — stop
allowed without a cost report once `blocks >= MAX_BLOCKS`; telemetry WAS
written), the stale-read allow (`agent_team_closeout.py:479–484` — same
shape), and a human-closed interactive session (the launcher runs an
interactive TUI, so `reconcile_lines` runs at every interactive start; an
operator who dispatches then closes the terminal before the forced closeout
leaves this exact signature). The original wording ("it likely died
mid-closeout … lost with the process") asserted a single cause the predicate
cannot actually distinguish. The line above replaces it: it asserts only the
observable STATE (no cost report, no pause) and enumerates the possible
causes without picking one. AC1's test asserts the substring `died
mid-closeout`, which still appears verbatim inside "may have **died
mid-closeout** (e.g. …)" — so AC1 is unaffected by this revision.

## False-positive negative cases (each a testable condition)

| # | Case | Condition that suppresses the warning |
|---|------|----------------------------------------|
| N1 | Intentionally paused session | `PAUSE_MARKER in last_text` → no warn |
| N2 | No specialist dispatches (plain / conversational) | `total == 0` → no warn |
| N3 | Normal closeout reached | `COST_MARKER in last_text` → no warn |
| N4 | The current session itself | excluded from discovery by absolute-path match |
| N5 | Garbage / unreadable prior transcript | `scan_transcript` returns `total == 0` (unparseable lines skipped, `errors="replace"`) → no warn, exit 0 |
| N6 | No prior transcript / no `transcript_path` / missing dir | discovery returns nothing → no warn |
| N7 | A newer plain session masks an older dead one | most-recent prior has `total == 0` → no warn (the stated masking trade) |

**Non-suppressed cases that share the dead signature (2026-07-26 revision).**
These are **not** false positives to suppress — they are legitimately
unreconciled sessions the warning is right to flag — but the wording must not
misattribute them to death:

| # | Case | Why the predicate still fires | Is it suppressed? |
|---|------|-------------------------------|--------------------|
| N8 | Enforcement-cap allow (`agent_team_closeout.py:420–424`) | Stop was allowed at `blocks >= MAX_BLOCKS` without ever getting a compliant cost report in `last_text`; telemetry WAS written but the final message still lacks `COST_MARKER` | No — warns (correctly: this session still lacks a human-readable cost report) |
| N9 | Stale-read allow (`agent_team_closeout.py:479–484`) | Same shape as N8: allowed without re-verification because the post-block reply hadn't flushed; `last_text` at warn-time may still lack `COST_MARKER` | No — warns |
| N10 | Human-closed interactive session | The launcher's TUI orchestrator runs `reconcile_lines` at every interactive start; an operator who dispatches specialists then closes the terminal before the forced closeout produces the identical `total>0`/no-marker signature | No — warns |

## Candidate (2) decision — launcher-side `-p` check: SCOPED OUT

`bin/agent-workforce` launches an **interactive TUI** orchestrator
(`claude --agent orchestrator --permission-mode bypassPermissions`, line 167–168)
and never invokes `claude -p`/`--print`; no `bin/` script does (a `-p`/`--print`
scan across the shell scripts finds only `mkdir -p` and unrelated flags). The
issue-8 dead session lived under an `…-scratchpad-e2e-design/` transcript dir — a
headless eval/e2e harness invoking `claude -p` directly, **outside** the
launcher. The launcher therefore does not own, wrap, or observe headless `-p`
runs, so a launcher-side check would have no runs to inspect. Candidate (2) is
scoped out; candidate (1) (next-session detection) is the whole fix.

## Designed-limitations prose to append to the checks-balances spec

Add the following bullet to the "Designed limitations (stated, not hidden)"
section of `docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md`,
immediately after the existing "**A killed agent fires no hooks of its own.**"
bullet (verbatim, this exact text — Task 3 inserts it):

```
- **A dead orchestrator is caught at the next start, not in real time
  (2026-07-26, issue #8).** The killed-agent limitation above has a partial
  close for the orchestrator itself: `session_start.py` (`reconcile_lines`)
  reads the single most-recent prior session transcript for the project and,
  when it shows specialist dispatches (`total > 0`) but its final message
  carries neither the closeout cost marker nor `WORKFORCE_PAUSE`, surfaces a
  `reconcile:` warning at the next launch. What this closes: a headless
  orchestrator that dies mid-closeout (e.g. `claude -p` exiting 0 on
  "Connection closed mid-response" after deliverables land but before the cost
  table prints) is no longer silent — the next session names it. What remains,
  stated plainly: (a) detection is deferred to the next session start, never
  real-time — nothing runs at the moment of death; (b) only the final report
  and telemetry are recoverable after the fact — the already-committed
  deliverables were never at risk, but any uncommitted tail dies with the
  process; (c) discovery inspects only the single most-recent prior transcript,
  so a plain session started before anyone reconciles will mask an older dead
  one — the deliberate trade that keeps the warning from nagging on every
  subsequent start forever; (d) the signal is a STATE, not a cause — any
  specialist-dispatching session that ends without a cost report or a pause
  trips it, which includes an enforcement-cap allow, a stale-read allow, and
  an operator closing an interactive session before the forced closeout, not
  only a genuine mid-process death. This is intentional: the state (no
  reconciled cost report) is what `scan_transcript` can actually detect; the
  cause is not, so the warning names the state and leaves the cause to the
  operator's inspection.
```

---

# Acceptance criteria (falsifiability-linted — lift verbatim into dispatches)

All Check commands run from `/Users/jay/claude/agent-workforce`. Single-test runs
use unittest's test-name selection; each prints `OK` on pass and a named
`AssertionError` on fail.

### AC1 — Positive detection: the dead-session fixture warns (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_dead_session_warns -v`
- **Expects:** `Ran 1 test` then `OK`. The test asserts the hook's
  `additionalContext` contains `reconcile:`, the dead transcript's basename
  (`dead.jsonl`), and `died mid-closeout`. On regression it fails with
  `AssertionError: 'reconcile:' not found` (or the missing substring).

### AC2 — N1 paused session does not warn (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_paused_session_no_warn -v`
- **Expects:** `OK`. Asserts `reconcile:` is **absent** from context when the
  prior's final message contains `WORKFORCE_PAUSE: HUMAN_DECISION`. A false
  positive fails with `AssertionError: 'reconcile:' unexpectedly found`.

### AC3 — N2 no-dispatch session does not warn (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_no_dispatch_session_no_warn -v`
- **Expects:** `OK`. Prior has `total == 0`; `reconcile:` absent.

### AC4 — N3 completed closeout does not warn (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_completed_closeout_no_warn -v`
- **Expects:** `OK`. Prior final message contains `## Cost report`;
  `reconcile:` absent.

### AC5 — N4 the current session is never self-flagged (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_current_session_not_flagged -v`
- **Expects:** `OK`. The only transcript present is the current one (dead-looking:
  dispatches, no closeout); it is excluded by path, so `reconcile:` is absent.

### AC6 — N6 missing `transcript_path` does not warn and does not crash (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_missing_transcript_path_no_warn -v`
- **Expects:** `OK`. Default payload (no `transcript_path`) yields exit 0 and no
  `reconcile:` line — proving existing tests that send no `transcript_path` are
  unaffected.

### AC7 — N5 garbage prior transcript fails open (mechanical)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_garbage_prior_fails_open -v`
- **Expects:** `OK`. A prior `*.jsonl` of non-JSON/binary bytes yields
  `returncode == 0` and no `reconcile:` line.

### AC8 — N7 a newer plain session masks an older dead one (mechanical, documents the trade)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_recent_clean_masks_older_dead -v`
- **Expects:** `OK`. With a dead prior (older mtime) and a plain prior (newer
  mtime), `reconcile:` is absent — the intended, stated non-nag behavior.

### AC9 — Positive multi-prior selection: the NEWEST prior is chosen, and warned on, over an older clean one (mechanical, 2026-07-26 addition)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_dead_newest_among_several_warns -v`
- **Expects:** `Ran 1 test` then `OK`. With several priors present — an OLDER
  clean one (`total == 0`, no dispatches) and a NEWER dead-signature one — the
  hook selects the highest-mtime prior and warns, naming the newest dead
  transcript's basename. This is the selection half of the masking trade AC8
  only tests the suppression half of: AC8 shows a newer clean session masks
  an older dead one; this shows that when the newest prior is itself the dead
  one, discovery correctly picks it (not an arbitrary or oldest prior) and
  warns. On regression it fails with `AssertionError: 'reconcile:' not found`
  or the wrong basename missing from context.

### AC10 — Empty-`last_text` death: a transcript that ends immediately after a tool_result, with no subsequent assistant text, still warns (mechanical, 2026-07-26 addition)
- **Check:** `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_empty_last_text_death_warns -v`
- **Expects:** `Ran 1 test` then `OK`. A prior with `total > 0` whose last
  record is a `tool_result` (so `scan_transcript` resets `tail_texts` on that
  `user`-typed record and appends nothing after) yields `last_text == ""` —
  neither `COST_MARKER` nor `PAUSE_MARKER` can be "in" an empty string, so the
  predicate is satisfied and the hook must warn. This is the most-silent death
  shape: no truncated final message at all, just nothing after the last tool
  result. On regression it fails with `AssertionError: 'reconcile:' not
  found`.

### AC11 — No regressions across the whole hook suite (mechanical)
- **Check:** `python3 tests/test_session_start.py -v`
- **Expects:** final line `OK` and `Ran N tests` where N equals the pre-change
  count plus the new tests (all 10 reconcile tests plus every pre-existing
  test). A single failing/errored test prints `FAILED (failures=…/errors=…)`.

### AC12 — No new dependencies (mechanical)
- **Check:** `python3 -c "import ast; src=open('hooks/session_start.py').read(); mods=sorted({(n.module or '').split('.')[0] if isinstance(n,ast.ImportFrom) else n.names[0].name.split('.')[0] for n in ast.walk(ast.parse(src)) if isinstance(n,(ast.Import,ast.ImportFrom))}); print(mods)"`
- **Expects exactly:** `['agent_team_closeout', 'json', 'os', 'subprocess', 'sys']`
  — every entry is Python stdlib except `agent_team_closeout` (a sibling hook
  module, not a PyPI package). Any additional name appearing in the list fails
  the criterion. (`ast.walk` captures the deferred in-function import too.)

### AC13 — Designed-limitations amendment landed (judgment)
- **Judge:** reviewer (fidelity mode).
- **Bar:** the exact bullet from the spec's "Designed-limitations prose"
  subsection is present in the "Designed limitations" section of
  `docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md`,
  positioned after the "A killed agent fires no hooks of its own" bullet, and
  states all four residuals: (a) deferred-not-real-time, (b) only report/
  telemetry lost while committed deliverables stand, (c) single-most-recent
  masking trade, (d) the signal is a state (no cost report, no pause) not a
  cause — it also fires on an enforcement-cap allow, a stale-read allow, and
  an operator-closed interactive session, not only a genuine death. A "no" is
  any of the four residuals missing or the claim overstating the close (e.g.
  implying real-time detection, or implying every warning means the process
  died).

---

# Implementation plan

## Task 1 — `reconcile_lines` in `hooks/session_start.py` (TDD)

**Files**
- Modify: `hooks/session_start.py` — add module constants `HERE`, `PAUSE_MARKER`;
  add function `reconcile_lines`; call it in `main()`.
- Test: `tests/test_session_start.py` — add helpers + AC1–AC8 test methods.

**Interfaces**
- Consumes from `agent_team_closeout` (existing, unchanged):
  `scan_transcript(path) -> (total, in_flight, roles, order, last_text)` and
  `COST_MARKER = "## Cost report"`.
- Produces: `reconcile_lines(payload: dict) -> list[str]` — 0 or 1 warning line;
  wired into the `lines` pipeline in `main()`.

**Steps**

1. [ ] Write the failing tests. Add these helpers to `SessionStartHookTest` (after
   `make_repo`), then the eight test methods:

   ```python
       # --- reconcile (dead-orchestrator detection, issue #8) ----------------

       def write_jsonl(self, path: Path, records: list) -> None:
           with open(path, "w", encoding="utf-8") as f:
               for rec in records:
                   f.write(json.dumps(rec) + "\n")

       def dispatch_rec(self, role: str = "builder", tid: str = "t1") -> dict:
           return {"type": "assistant", "message": {"content": [
               {"type": "tool_use", "name": "Agent", "id": tid,
                "input": {"subagent_type": role}}]}}

       def tool_result_rec(self, tid: str = "t1") -> dict:
           return {"type": "user", "message": {"content": [
               {"type": "tool_result", "tool_use_id": tid, "content": "done"}]}}

       def assistant_text_rec(self, text: str) -> dict:
           return {"type": "assistant", "message": {"content": [
               {"type": "text", "text": text}]}}

       def txdir(self) -> Path:
           d = self.root / "transcripts"
           d.mkdir(exist_ok=True)
           return d

       def with_transcript(self, transcript: Path) -> str:
           return json.dumps({"cwd": str(self.root),
                              "transcript_path": str(transcript)})

       def test_reconcile_dead_session_warns(self) -> None:
           d = self.txdir()
           dead = d / "dead.jsonl"
           self.write_jsonl(dead, [
               self.dispatch_rec("builder", "t1"),
               self.tool_result_rec("t1"),
               self.assistant_text_rec(
                   "Now the cost report. Locating my transcript to run the "
                   "reporter."),
               {"type": "assistant", "isApiErrorMessage": True,
                "message": {"content": [{"type": "text", "text":
                   "API Error: Connection closed mid-response."}]}},
           ])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(dead, (1000, 1000))
           os.utime(current, (2000, 2000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertIn("reconcile:", ctx)
           self.assertIn("dead.jsonl", ctx)
           self.assertIn("died mid-closeout", ctx)

       def test_reconcile_paused_session_no_warn(self) -> None:
           d = self.txdir()
           prior = d / "paused.jsonl"
           self.write_jsonl(prior, [
               self.dispatch_rec("architect", "t1"),
               self.tool_result_rec("t1"),
               self.assistant_text_rec(
                   "Design done. WORKFORCE_PAUSE: HUMAN_DECISION — awaiting gate."),
           ])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertNotIn("reconcile:", ctx)

       def test_reconcile_no_dispatch_session_no_warn(self) -> None:
           d = self.txdir()
           prior = d / "chat.jsonl"
           self.write_jsonl(prior, [
               self.assistant_text_rec("Just a conversation, no dispatches.")])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertNotIn("reconcile:", ctx)

       def test_reconcile_completed_closeout_no_warn(self) -> None:
           d = self.txdir()
           prior = d / "done.jsonl"
           self.write_jsonl(prior, [
               self.dispatch_rec("builder", "t1"),
               self.tool_result_rec("t1"),
               self.assistant_text_rec(
                   "All shipped.\n\n## Cost report\n| total | $1.23 |"),
           ])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertNotIn("reconcile:", ctx)

       def test_reconcile_current_session_not_flagged(self) -> None:
           d = self.txdir()
           current = d / "current.jsonl"
           self.write_jsonl(current, [
               self.dispatch_rec("builder", "t1"),
               self.tool_result_rec("t1"),
               self.assistant_text_rec("Working... no closeout yet."),
           ])
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertNotIn("reconcile:", ctx)

       def test_reconcile_missing_transcript_path_no_warn(self) -> None:
           ctx = self.context(self.run_hook(self.root))
           self.assertNotIn("reconcile:", ctx)

       def test_reconcile_garbage_prior_fails_open(self) -> None:
           d = self.txdir()
           prior = d / "garbage.jsonl"
           prior.write_text("not json\n\x00 broken line\n", encoding="latin-1")
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
           result = self.run_hook(self.root, raw=self.with_transcript(current))
           self.assertEqual(result.returncode, 0, result.stderr)
           self.assertNotIn("reconcile:", self.context(result))

       def test_reconcile_recent_clean_masks_older_dead(self) -> None:
           d = self.txdir()
           dead = d / "dead.jsonl"
           self.write_jsonl(dead, [
               self.dispatch_rec("builder", "t1"),
               self.tool_result_rec("t1"),
               self.assistant_text_rec("No closeout — I died."),
           ])
           clean = d / "clean.jsonl"
           self.write_jsonl(clean, [
               self.assistant_text_rec("Quick chat, nothing dispatched.")])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(dead, (1000, 1000)); os.utime(clean, (2000, 2000))
           os.utime(current, (3000, 3000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertNotIn("reconcile:", ctx)

       # --- added 2026-07-26 (plan-critique SHIP-WITH-FIXES, AC9/AC10) -------

       def test_reconcile_dead_newest_among_several_warns(self) -> None:
           d = self.txdir()
           older_clean = d / "older_clean.jsonl"
           self.write_jsonl(older_clean, [
               self.assistant_text_rec("Quick chat, nothing dispatched.")])
           newest_dead = d / "newest_dead.jsonl"
           self.write_jsonl(newest_dead, [
               self.dispatch_rec("builder", "t1"),
               self.tool_result_rec("t1"),
               self.assistant_text_rec("No closeout — I died too."),
           ])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(older_clean, (1000, 1000))
           os.utime(newest_dead, (2000, 2000))
           os.utime(current, (3000, 3000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertIn("reconcile:", ctx)
           self.assertIn("newest_dead.jsonl", ctx)

       def test_reconcile_empty_last_text_death_warns(self) -> None:
           d = self.txdir()
           dead = d / "silent_death.jsonl"
           self.write_jsonl(dead, [
               self.dispatch_rec("builder", "t1"),
               self.tool_result_rec("t1"),
           ])
           current = d / "current.jsonl"
           current.write_text("", encoding="utf-8")
           os.utime(dead, (1000, 1000)); os.utime(current, (2000, 2000))
           ctx = self.context(self.run_hook(self.root,
                                            raw=self.with_transcript(current)))
           self.assertIn("reconcile:", ctx)
           self.assertIn("silent_death.jsonl", ctx)
   ```

2. [ ] Run the new tests — they must fail because `reconcile_lines` does not
   exist yet (the hook emits no `reconcile:` line):
   `python3 tests/test_session_start.py SessionStartHookTest.test_reconcile_dead_session_warns -v`
   Expected failure: `AssertionError: 'reconcile:' not found in '…'`.

3. [ ] Write the minimal implementation. In `hooks/session_start.py`, after the
   existing `PROJECT_FILE = …` line (top-of-module constants, before `def run`),
   add:

   ```python
   HERE = os.path.dirname(os.path.abspath(__file__))
   PAUSE_MARKER = "WORKFORCE_PAUSE: HUMAN_DECISION"
   ```

   Then add this function (place it just before `def main():`):

   ```python
   def reconcile_lines(payload):
       """Catch an orchestrator that died mid-closeout, at the NEXT start.

       Why it exists: a headless `claude -p` orchestrator that dies after
       deliverables commit but before the closeout cost table prints still
       exits 0, and a killed process fires no Stop hook — so
       agent_team_closeout never grades the truncated final message and the
       death is silent (issue #8, observed live 2026-07-26). Detection must
       live at a consumption point that survives the death: the next session's
       start.

       Discovery: the current session's transcript_path names the per-project
       transcript directory; prior sessions are its sibling *.jsonl files.
       Inspect ONLY the single most-recent prior (highest mtime, excluding the
       current transcript by absolute path) — bounded to one extra scan and
       self-clearing, so the warning never nags across unrelated later
       sessions (a later plain session masking an older dead one is the
       accepted trade).

       Predicate (all must hold to warn): the prior had specialist dispatches
       (total > 0) AND its final message carries neither COST_MARKER (a normal
       closeout) NOR PAUSE_MARKER (an intentional human-decision pause).

       :param payload: the SessionStart hook payload dict; uses
           transcript_path.
       :returns: a one-element list with the operator warning, or [] when
           there is nothing to reconcile.
       :raises: nothing — every failure path returns [] (main() also
           try/excepts this call).
       """
       if not isinstance(payload, dict):
           return []
       transcript = payload.get("transcript_path")
       if not isinstance(transcript, str) or not transcript:
           return []
       tdir = os.path.dirname(transcript)
       if not os.path.isdir(tdir):
           return []
       current = os.path.abspath(transcript)
       priors = []
       for name in os.listdir(tdir):
           if not name.endswith(".jsonl"):
               continue
           path = os.path.join(tdir, name)
           if os.path.abspath(path) == current:
               continue
           try:
               priors.append((os.path.getmtime(path), path))
           except OSError:
               continue
       if not priors:
           return []
       priors.sort()
       prior = priors[-1][1]
       sys.path.insert(0, HERE)
       from agent_team_closeout import scan_transcript, COST_MARKER
       total, _in_flight, _roles, _order, last_text = scan_transcript(prior)
       if total == 0:
           return []
       if COST_MARKER in last_text or PAUSE_MARKER in last_text:
           return []
       name = os.path.basename(prior)
       return ["reconcile: prior session " + name + " dispatched specialists "
               "but ended without a closeout cost report or a "
               "WORKFORCE_PAUSE. It may have died mid-closeout (e.g. a "
               "headless run whose connection dropped after deliverables "
               "committed but before the cost table printed), been "
               "interrupted/closed by the operator, or been allowed to stop "
               "at the enforcement cap. Committed deliverables are "
               "unaffected; the final report/telemetry for this session may "
               "be missing. Inspect " + prior + " — recover the numbers with "
               "`bin/agent-workforce-cost-report --transcript " + prior + "`."]
   ```

   Then wire it into `main()`, immediately after the `launch_mode_lines()`
   try/except block and before the `git_sync_lines` block:

   ```python
       try:
           lines.extend(reconcile_lines(payload))
       except Exception:
           pass
   ```

4. [ ] Run the reconcile tests and the whole suite — expected pass:
   `python3 tests/test_session_start.py -v`
   Expected: `OK`, `Ran N tests` (pre-existing + 10 new).
   Also run AC12: the import list is
   `['agent_team_closeout', 'json', 'os', 'subprocess', 'sys']`.

5. [ ] Commit:
   `git -C /Users/jay/claude/agent-workforce add hooks/session_start.py tests/test_session_start.py && git -C /Users/jay/claude/agent-workforce commit -m "fix(session-start): reconcile a dead-mid-closeout orchestrator at next start (#8)"`

## Task 2 — Amend the designed-limitations section (docs only)

**Files**
- Modify: `docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md`.

**Steps**

1. [ ] Insert the exact bullet from the spec's "Designed-limitations prose to
   append" subsection above, immediately after the existing bullet
   "**A killed agent fires no hooks of its own.**" (currently the last bullet of
   the "Designed limitations" section, around line 213–215).

2. [ ] Verify placement and completeness (AC13): the new bullet follows the
   killed-agent bullet and names all four residuals.
   `grep -n "dead orchestrator is caught at the next start" docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md`
   Expected: one match, located after the killed-agent bullet.

3. [ ] Commit:
   `git -C /Users/jay/claude/agent-workforce add docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md && git -C /Users/jay/claude/agent-workforce commit -m "docs(spec): record issue-8 partial close + residual limitation"`

---

# Self-review

- **Coverage — every spec requirement maps to a task.** Predicate + discovery +
  warning text → Task 1 code (step 3). Each false-positive N1–N7 → AC2–AC8 tests
  (Task 1). The non-suppressed shared-signature cases N8–N10 (enforcement-cap
  allow, stale-read allow, human-closed session) → documented in the
  false-positive table and the designed-limitations residual (d); no separate
  AC because they are not suppressed — they warn, same as any other dead
  signature, which AC1/AC9/AC10 already exercise. Selection-of-newest → AC9.
  Empty-`last_text` death → AC10. Fail-open on garbage/missing → AC6/AC7. No
  new deps → AC12. Candidate-(2) decision → spec section (no code, correctly).
  Designed-limitations prose (now four residuals) → Task 2 / AC13. No gaps.
- **Placeholder scan.** No "TBD/TODO/implement later/similar to Task N"; every
  step shows the actual code and the exact command with its expected output.
- **Consistency.** `scan_transcript`'s 5-tuple and `COST_MARKER` match
  `hooks/agent_team_closeout.py` (lines 50, 126, 191). `PAUSE_MARKER` string
  matches the literal used throughout that module. The import idiom
  (`sys.path.insert(0, HERE)` then `from agent_team_closeout import …`) matches
  the established `debug_run_archiver.py` pattern. `run_hook(cwd, raw=…)` and
  `context()` match the existing test harness signatures. The AC12 expected
  import set matches the module's actual imports after the change. The
  revised warning text (2026-07-26) still contains the exact substring `died
  mid-closeout` that AC1 asserts, and both copies (spec section and Task-1
  code block) are byte-identical, satisfying the "keep them identical"
  instruction. The reconcile test count referenced in AC11 and Task-1 step 4
  is 10 throughout (8 original + 2 added), consistent everywhere it appears.
