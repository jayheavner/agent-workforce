# Exact Closeout Cost Accounting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PostToolUse hook that sums exact per-request token usage from session transcripts into a per-session cost file, and teach the orchestrator to emit an exact per-model cost table at the final gate, falling back to the existing blended estimate whenever exact data is absent or unavailable.

**Architecture:** A new bash hook (`hooks/agent-team-cost.sh`), registered on the orchestrator's `PostToolUse` / matcher `Agent`, fires after each dispatch completes. Each fire scans the completed session's per-dispatch subagent JSONL files, dedups streaming snapshots by `message.id`, prices each request against a rates config (`hooks/model-rates.json`), and writes a per-session JSON cost file under `~/.claude/logs/agent-team-cost/`. Incrementality is at file granularity: a dispatch file is re-parsed only when its byte size changes. On any unrecognized format the hook writes a sticky `"status":"unavailable"` marker and exits 0 — it never emits a wrong number. The orchestrator prefers the exact file when present and `"ok"`, otherwise uses its existing blended-estimate table.

**Tech Stack:** bash (`#!/usr/bin/env bash`, `set -u`), jq (already required by the repo). No new packages.

**Reference spec:** `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md` (APPROVED). Read it before starting. Component numbers below (Component 1–6) map to that spec.

> **Amendment 2026-07-09 (post-implementation correctness fix + 3 nits).** Tasks 1–13 already
> shipped. Code review found that the sticky-unavailable path is too eager: any sibling dispatch
> file caught mid-write (0-byte, or a truncated final line) trips the whole-file parse, writes the
> sticky marker, and — via the sticky early-return — permanently pins the session to
> `"unavailable"`, defeating the D7 self-heal the spec promised. **Tasks 14–17 below** fix this and
> fold in three review nits. They are ordered test-first and touch only the delta; Tasks 1–13 stay
> as-is. See the spec's dated amendments (§D7, Component 1 step 5, Components 6) for the precise
> two-mode behavior. Run Task 17 (full acceptance) after the delta tasks.

## Global Constraints

Copied verbatim from the spec and the repo's fixed constraints — every task's requirements implicitly include this section:

- **bash + jq only. No new packages** (pip, npm, or otherwise). jq is already required; `install.sh:23` hard-fails without it.
- **No file deletion or moves in any step.** No `rm`, no `mv`. The cost file is written with a single-shot `printf '%s' ... > "$file"` redirect (no temp-file-plus-mv). All doc/source edits are in-place via Edit/Write. (The installer already contains its own `rm -f`/`mktemp` for rollback and manifest — that is pre-existing installer code you extend, not new deletion steps you author elsewhere.)
- **Config in config files, never hardcoded.** All prices live only in `hooks/model-rates.json`. The script contains zero numeric rates.
- **Files under ~300 lines.** `hooks/agent-team-cost.sh` and `tests/test_cost_hook.sh` each stay under 300 lines.
- **Config-safety for self-modifying files** (applies to the installer task): write the hook/JSON to their destination only after validating the repo copies — `bash -n` for the script, `jq empty` plus a shape check for the JSON — following `install.sh`'s existing validate → back up → install → rollback pattern.
- **The hook always exits 0.** PostToolUse cannot block; any error path writes the unavailable marker (or nothing) and exits 0.
- **Never a wrong number.** Any recognition failure, unreadable rates file, or internal jq error → sticky `"status":"unavailable"` marker, never partial/guessed totals.
- **Hook conventions match the policy hook:** `#!/usr/bin/env bash`, `set -u`, `INPUT="$(cat)"` slurped once, jq for all JSON, env-var overrides for output location (`AGENT_TEAM_COST_DIR`) and rates path (`AGENT_TEAM_RATES`), and sibling-file resolution via `"$(cd "$(dirname "$0")" && pwd)"`.

### Verified rates (spec §D8 / Component 2) — the ONLY place numbers live

Per million tokens, USD. `claude-sonnet-5` has an intro block through `2026-08-31`.

| Model | input | output | cache_write_5m | cache_write_1h | cache_read |
|---|---|---|---|---|---|
| claude-haiku-4-5 | 1.00 | 5.00 | 1.25 | 2.00 | 0.10 |
| claude-sonnet-5 | 3.00 | 15.00 | 3.75 | 6.00 | 0.30 |
| claude-sonnet-5 intro (ends 2026-08-31) | 2.00 | 10.00 | 2.50 | 4.00 | 0.20 |
| claude-opus-4-8 | 5.00 | 25.00 | 6.25 | 10.00 | 0.50 |
| claude-fable-5 | 10.00 | 50.00 | 12.50 | 20.00 | 1.00 |

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `hooks/model-rates.json` | Rates config — the sole home of all prices | Task 1 |
| `tests/fixtures/cost/` | Committed transcript fixtures (good / malformed / unknown-model) laid out as a fake project dir | Task 2 |
| `tests/test_cost_hook.sh` | Fixture-driven test suite (executable spec, policy-test style) | Tasks 3–8 (grown incrementally) |
| `hooks/agent-team-cost.sh` | The PostToolUse cost-accounting hook | Tasks 3–8 (grown incrementally) |
| `install.sh` | Validate + install the two new hook files, run the new suite | Task 9 |
| `agents/orchestrator.md` | Frontmatter hooks block; two-path closeout section | Task 10 |
| `README.md` | Closeout wording, install validation list, Cost accounting section | Task 11 |
| `docs/superpowers/specs/2026-07-07-ai-agent-team-design.md` | Dated amendment note — deferred item shipped | Task 12 |
| `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md` | Status flip Proposed → Accepted/shipped | Task 12 |

**Build order rationale:** Task 1 (rates) has no dependencies and everything prices against it. Task 2 (fixtures) is pure data the tests consume. Tasks 3–8 grow the hook and its tests together, one behavior at a time, each with the failing test written before the implementation. Task 9 (installer) can only pass once the hook, rates, and tests exist. Tasks 10–12 are doc/config edits gated on the hook's file schema being final. Task 13 is the final full-suite + installer acceptance run.

---

## Task 1: Rates config (Component 2)

**Files:**
- Create: `hooks/model-rates.json`

**Interfaces:**
- Produces: JSON document with top-level `comment`, `as_of`, and `models`. Each model under `.models` carries five numeric rate keys — `input`, `output`, `cache_write_5m`, `cache_write_1h`, `cache_read` — and `claude-sonnet-5` additionally carries an `intro` object with `ends` (ISO date string) plus the same five numeric keys. The hook (Task 6) and the installer shape-check (Task 9) both consume exactly this shape.

- [ ] **Step 1: Write the rates file**

Create `hooks/model-rates.json` with exactly this content:

```json
{
  "comment": "USD per million tokens. Source: Anthropic list prices. Edit + reinstall to change.",
  "as_of": "2026-07-08",
  "models": {
    "claude-haiku-4-5": { "input": 1.00, "output": 5.00,
      "cache_write_5m": 1.25, "cache_write_1h": 2.00, "cache_read": 0.10 },
    "claude-sonnet-5": { "input": 3.00, "output": 15.00,
      "cache_write_5m": 3.75, "cache_write_1h": 6.00, "cache_read": 0.30,
      "intro": { "ends": "2026-08-31",
        "input": 2.00, "output": 10.00,
        "cache_write_5m": 2.50, "cache_write_1h": 4.00, "cache_read": 0.20 } },
    "claude-opus-4-8": { "input": 5.00, "output": 25.00,
      "cache_write_5m": 6.25, "cache_write_1h": 10.00, "cache_read": 0.50 },
    "claude-fable-5": { "input": 10.00, "output": 50.00,
      "cache_write_5m": 12.50, "cache_write_1h": 20.00, "cache_read": 1.00 }
  }
}
```

- [ ] **Step 2: Validate it parses and has the required shape**

Run:
```bash
jq empty hooks/model-rates.json && \
jq -e '[.models[] | [.input,.output,.cache_write_5m,.cache_write_1h,.cache_read] | all(type=="number")] | all' hooks/model-rates.json
```
Expected: no error, and the second command prints `true`.

- [ ] **Step 3: Commit**

```bash
git add hooks/model-rates.json
git commit -m "feat: add model-rates.json rates config for cost accounting"
```

---

## Task 2: Transcript fixtures (Component 5, data)

Fixtures are laid out as a fake project directory so the hook resolves the subagents dir from `transcript_path` exactly as in production: given `transcript_path = <dir>/<sid>.jsonl`, the subagents dir is `<dir>/<sid>/subagents/`.

**Files:**
- Create: `tests/fixtures/cost/good/<SID>.jsonl` (main transcript — minimal, no sidechain records)
- Create: `tests/fixtures/cost/good/<SID>/subagents/agent-aaaa1111.jsonl` (opus dispatch)
- Create: `tests/fixtures/cost/good/<SID>/subagents/agent-bbbb2222.jsonl` (sonnet dispatch)
- Create: `tests/fixtures/cost/malformed/<SID>/subagents/agent-cccc3333.jsonl` (one non-JSON line)
- Create: `tests/fixtures/cost/unknown/<SID>/subagents/agent-dddd4444.jsonl` (valid, model not in rates)

Use `SID = 11111111-2222-3333-4444-555555555555` for all three fixture trees (any fixed UUID-shaped string; the hook does not validate its shape).

**Interfaces:**
- Produces: committed JSONL files with the exact token values below. The test file (Task 3) hand-computes costs from these values; the numbers here and the assertions there must agree.

**Hand-computed truth for the good fixture** (this block is the executable spec — it is repeated verbatim as a comment in `tests/test_cost_hook.sh`):

```
Dispatch A = agent-aaaa1111, agent_type "architect", model claude-opus-4-8
  msg A1 (single line):        input 1000, cw5m 2000, cw1h 0, cr 4000, out 500
    cost = (1000*5 + 500*25 + 2000*6.25 + 0*10 + 4000*0.5)/1e6 = 32000/1e6 = 0.0320
  msg A2 (3 dedup snapshots, identical in/cache, out grows 100->300->600):
                               input 2000, cw5m 0,    cw1h 0, cr 8000, out 600 (max)
    cost = (2000*5 + 600*25 + 0 + 0 + 8000*0.5)/1e6 = 29000/1e6 = 0.0290
  Dispatch A opus totals: input 3000, output 1100, cw5m 2000, cw1h 0, cr 12000
    requests 2, cost 0.0610

Dispatch B = agent-bbbb2222, agent_type "researcher", model claude-sonnet-5
  msg B1 (INTRO priced, ts 2026-08-15, cache_creation split 5m=1000 1h=500):
                               input 4000, cw5m 1000, cw1h 500, cr 10000, out 800
    intro rates (in2 out10 cw5m2.5 cw1h4 cr0.2)
    cost = (4000*2 + 800*10 + 1000*2.5 + 500*4 + 10000*0.2)/1e6 = 22500/1e6 = 0.0225
  msg B2 (STANDARD priced, ts 2026-09-01):
                               input 6000, cw5m 0, cw1h 0, cr 0, out 1000
    std rates (in3 out15)
    cost = (6000*3 + 1000*15)/1e6 = 33000/1e6 = 0.0330
  Dispatch B sonnet totals: input 10000, output 1800, cw5m 1000, cw1h 500, cr 10000
    requests 2, cost 0.0555

GRAND TOTALS
  claude-opus-4-8:   input 3000, output 1100, cw5m 2000, cw1h 0,   cr 12000, cost 0.0610
  claude-sonnet-5:   input 10000, output 1800, cw5m 1000, cw1h 500, cr 10000, cost 0.0555
  grand cost = 0.1165
```

- [ ] **Step 1: Create the good main transcript (no sidechain usage)**

Create `tests/fixtures/cost/good/11111111-2222-3333-4444-555555555555.jsonl` with one benign non-assistant line so the file exists but contributes no usage (the hook only reads the subagents dir; this file is present to mirror the real layout):

```json
{"type":"user","uuid":"u1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T00:00:00.000Z"}
```

- [ ] **Step 2: Create Dispatch A (opus) — dedup + single-line record**

Create `tests/fixtures/cost/good/11111111-2222-3333-4444-555555555555/subagents/agent-aaaa1111.jsonl`. One line for A1, then three snapshot lines for A2 sharing `message.id` `msg_A2` with identical input/cache and growing `output_tokens` (100, 300, 600). Only usage-bearing fields matter; keep envelopes minimal but valid:

```json
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A1","uuid":"a1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A1","type":"message","role":"assistant","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":4000,"cache_creation":{"ephemeral_5m_input_tokens":2000,"ephemeral_1h_input_tokens":0},"output_tokens":500}}}
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A2","uuid":"a2a","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:01:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A2","type":"message","role":"assistant","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":100}}}
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A2","uuid":"a2b","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:01:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A2","type":"message","role":"assistant","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":300}}}
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A2","uuid":"a2c","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:01:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A2","type":"message","role":"assistant","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":600}}}
```

Note: A2 has no `cache_creation` sub-object and `cache_creation_input_tokens` is 0, exercising the "write attributed to 5m when the split object is absent" rule (here the write is zero, so it is trivially correct and also covers the absent-sub-object path).

- [ ] **Step 3: Create Dispatch B (sonnet) — intro vs standard pricing + 5m/1h split**

Create `tests/fixtures/cost/good/11111111-2222-3333-4444-555555555555/subagents/agent-bbbb2222.jsonl`:

```json
{"type":"assistant","isSidechain":true,"agentId":"bbbb2222","requestId":"req_B1","uuid":"b1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-08-15T12:00:00.000Z","message":{"model":"claude-sonnet-5","id":"msg_B1","type":"message","role":"assistant","usage":{"input_tokens":4000,"cache_creation_input_tokens":1500,"cache_read_input_tokens":10000,"cache_creation":{"ephemeral_5m_input_tokens":1000,"ephemeral_1h_input_tokens":500},"output_tokens":800}}}
{"type":"assistant","isSidechain":true,"agentId":"bbbb2222","requestId":"req_B2","uuid":"b2","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-09-01T09:00:00.000Z","message":{"model":"claude-sonnet-5","id":"msg_B2","type":"message","role":"assistant","usage":{"input_tokens":6000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1000}}}
```

- [ ] **Step 4: Create the malformed fixture**

Create `tests/fixtures/cost/malformed/11111111-2222-3333-4444-555555555555/subagents/agent-cccc3333.jsonl` — a valid first line, then a line that is not JSON:

```
{"type":"assistant","isSidechain":true,"agentId":"cccc3333","requestId":"req_C1","uuid":"c1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_C1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}
this line is not valid json {{{
```

- [ ] **Step 5: Create the unknown-model fixture**

Create `tests/fixtures/cost/unknown/11111111-2222-3333-4444-555555555555/subagents/agent-dddd4444.jsonl` — valid JSON, but `.message.model` is not in the rates file:

```json
{"type":"assistant","isSidechain":true,"agentId":"dddd4444","requestId":"req_D1","uuid":"d1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-nonexistent-9","id":"msg_D1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}
```

- [ ] **Step 6: Sanity-check the valid fixtures parse line-by-line**

Run:
```bash
for f in tests/fixtures/cost/good/*/subagents/*.jsonl tests/fixtures/cost/unknown/*/subagents/*.jsonl; do
  while IFS= read -r line; do printf '%s' "$line" | jq empty || echo "BAD LINE in $f"; done < "$f"
done
```
Expected: no output (every line in the good and unknown fixtures is valid JSON). The malformed fixture is intentionally not checked here.

- [ ] **Step 7: Commit**

```bash
git add tests/fixtures/cost
git commit -m "test: add cost-hook transcript fixtures (good/malformed/unknown)"
```

---

## Task 3: Test harness + hook skeleton (locate paths, always exit 0)

Build the test file's harness and the hook's first behavior together: given a valid stdin payload, the hook resolves its paths, produces a cost file at the expected location, and exits 0. Later tasks fill in parsing and pricing.

**Files:**
- Create: `tests/test_cost_hook.sh`
- Create: `hooks/agent-team-cost.sh`

**Interfaces:**
- Produces (hook): reads stdin JSON with fields `session_id`, `transcript_path`, `cwd`, `tool_response.agentId`, `tool_response.agentType`. Writes cost file to `$AGENT_TEAM_COST_DIR/<cwd-slug>--<session_id>.json` where `<cwd-slug>` is `cwd` with every `/` replaced by `-`. Reads rates from `$AGENT_TEAM_RATES` (default: `model-rates.json` in the script's own dir). Always exits 0.
- Produces (test harness): `run_hook <stdin-json>` sets global `RC`; `costfile_for <cwd> <sid>` echoes the expected cost-file path; `PASS`/`FAIL` counters; final line `passed=N failed=M`; nonzero exit on any failure. `payload <cwd> <transcript_path> <sid> <agentId> <agentType>` builds a stdin JSON via jq.

- [ ] **Step 1: Write the failing test — harness + case that a valid fire writes an ok cost file**

Create `tests/test_cost_hook.sh`. Include the good-fixture hand-math (Task 2 block) verbatim as a comment near the top. Harness plus first assertion:

```bash
#!/usr/bin/env bash
# tests/test_cost_hook.sh — executable form of the cost-accounting hook spec.
# Hand-computed truth for the good fixture (see also tests/fixtures/cost/):
#   [paste the Task 2 "Hand-computed truth" block here verbatim, each line prefixed with '# ']
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
HOOK="$REPO/hooks/agent-team-cost.sh"
FIXROOT="$HERE/fixtures/cost"
SID="11111111-2222-3333-4444-555555555555"
CWD="/fake/project"                          # slug -> -fake-project
SLUG="-fake-project"
SCRATCH="$(mktemp -d)"
export AGENT_TEAM_COST_DIR="$SCRATCH/costfiles"
export AGENT_TEAM_RATES="$REPO/hooks/model-rates.json"
PASS=0; FAIL=0; RC=0

payload() { # $1 cwd, $2 transcript_path, $3 sid, $4 agentId, $5 agentType
  jq -cn --arg cwd "$1" --arg tp "$2" --arg sid "$3" --arg aid "$4" --arg at "$5" \
    '{session_id:$sid, transcript_path:$tp, cwd:$cwd, hook_event_name:"PostToolUse",
      tool_name:"Agent", tool_response:{agentId:$aid, agentType:$at}}'
}
run_hook() { set +e; printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1; RC=$?; set -u; }
costfile_for() { printf '%s/%s--%s.json' "$AGENT_TEAM_COST_DIR" "$2" "$3"; }  # $2 slug, $3 sid
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

GOOD_TP="$FIXROOT/good/$SID.jsonl"
CF="$(costfile_for "$CWD" "$SLUG" "$SID")"

# Case: a valid fire writes a cost file at the slugged path and exits 0.
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
[ "$RC" -eq 0 ] && ok || no "valid fire exits 0"
[ -f "$CF" ] && ok || no "valid fire writes cost file at slugged path"
jq -e '.status=="ok"' "$CF" >/dev/null 2>&1 && ok || no "valid fire status ok"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_cost_hook.sh`
Expected: FAIL — the hook file does not exist yet, so `run_hook` produces RC != 0 and no cost file.

- [ ] **Step 3: Write the minimal hook — path resolution, empty ok cost file, always exit 0**

Create `hooks/agent-team-cost.sh`:

```bash
#!/usr/bin/env bash
# agent-team-cost.sh — PostToolUse(Agent) hook: sums exact per-request token
# usage from this session's per-dispatch subagent transcripts into a per-session
# cost file, priced from model-rates.json. Never blocks, never emits a wrong
# number: on any unrecognized input it writes a sticky "unavailable" marker and
# exits 0. See docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md.
set -u

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.tool_response.agentId // empty')"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.tool_response.agentType // "unknown"')"

# Cannot even locate a cost file safely -> write nothing, exit 0.
[ -n "$SESSION_ID" ] || exit 0
[ -n "$TRANSCRIPT" ] || exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
RATES="${AGENT_TEAM_RATES:-$HERE/model-rates.json}"
COST_DIR="${AGENT_TEAM_COST_DIR:-$HOME/.claude/logs/agent-team-cost}"
SUBAGENTS_DIR="${TRANSCRIPT%.jsonl}/subagents"
SLUG="$(printf '%s' "$CWD" | tr '/' '-')"
COST_FILE="$COST_DIR/$SLUG--$SESSION_ID.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$COST_DIR"

# write_unavailable REASON -> sticky marker, exit 0.
write_unavailable() {
  printf '%s' "$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" --arg r "$1" \
    '{version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"unavailable", unavailable_reason:$r}')" \
    > "$COST_FILE"
  exit 0
}

# --- minimal for Task 3: write an empty ok document. Filled in by later tasks. ---
printf '%s' "$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" \
  '{version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"ok",
    dispatches:{}, totals:{models:{}, cost_usd:0, web_search_requests:0, web_fetch_requests:0}}')" \
  > "$COST_FILE"
exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_cost_hook.sh`
Expected: `passed=3 failed=0`, exit 0.

- [ ] **Step 5: Verify missing-field guard writes nothing**

Add to the test (before the `echo "passed=..."` line):

```bash
# Case: missing session_id -> write nothing, exit 0.
NOSID="$SCRATCH/costfiles/-fake-project--.json"
run_hook "$(jq -cn --arg cwd "$CWD" --arg tp "$GOOD_TP" '{transcript_path:$tp, cwd:$cwd, tool_response:{agentId:"x"}}')"
[ "$RC" -eq 0 ] && ok || no "missing session_id exits 0"
[ ! -f "$NOSID" ] && ok || no "missing session_id writes nothing"
```

Run: `bash tests/test_cost_hook.sh`
Expected: `passed=5 failed=0` (the guard already exists in the hook from Step 3).

- [ ] **Step 6: Commit**

```bash
git add tests/test_cost_hook.sh hooks/agent-team-cost.sh
git commit -m "feat: cost hook skeleton — path resolution and always-exit-0"
```

---

## Task 4: Parse one dispatch file — dedup, sum, price (the core)

Add the per-dispatch parse-and-price logic and assert the good fixture reproduces the hand math exactly. This is the heart of Acceptance Criterion 1.

**Files:**
- Modify: `hooks/agent-team-cost.sh`
- Modify: `tests/test_cost_hook.sh`

**Interfaces:**
- Produces (cost-file schema, per the spec's Component 3): under `.dispatches["<agentId>"]`: `agent_type`, `file`, `file_size` (integer bytes), `requests` (integer), `web_search_requests`, `web_fetch_requests`, and `models["<model>"]` carrying `input_tokens`, `output_tokens`, `cache_write_5m_tokens`, `cache_write_1h_tokens`, `cache_read_tokens`, `cost_usd` (unrounded float). `.totals` aggregates the same per-model shape plus a grand `cost_usd`, `web_search_requests`, `web_fetch_requests`. These exact key names are consumed by the idempotency/incremental tests (Task 5) and the orchestrator table (Task 10).

- [ ] **Step 1: Write the failing tests — good fixture reproduces the hand math**

Add to `tests/test_cost_hook.sh`, before the `echo "passed=..."` line. The hook must, on a fire naming dispatch A, scan the whole subagents dir and pick up BOTH A and B (D4: scan all files, not just the fired one):

```bash
# --- Task 4: exact math over the good fixture (fire once, whole dir scanned) ---
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
j() { jq -r "$1" "$CF"; }   # read a path out of the cost file

# Dispatch A (opus)
[ "$(j '.dispatches.aaaa1111.agent_type')" = "architect" ] && ok || no "A agent_type"
[ "$(j '.dispatches.aaaa1111.requests')" = "2" ] && ok || no "A requests=2 (dedup)"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".input_tokens')" = "3000" ] && ok || no "A opus input"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".output_tokens')" = "1100" ] && ok || no "A opus output (dedup max 600+500)"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cache_write_5m_tokens')" = "2000" ] && ok || no "A opus cw5m"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cache_write_1h_tokens')" = "0" ] && ok || no "A opus cw1h"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cache_read_tokens')" = "12000" ] && ok || no "A opus cr"
[ "$(j '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd')" = "0.061" ] && ok || no "A opus cost 0.061"

# Dispatch B (sonnet) — intro + standard + 5m/1h split
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".input_tokens')" = "10000" ] && ok || no "B sonnet input"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".output_tokens')" = "1800" ] && ok || no "B sonnet output"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cache_write_5m_tokens')" = "1000" ] && ok || no "B sonnet cw5m"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cache_write_1h_tokens')" = "500" ] && ok || no "B sonnet cw1h"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cache_read_tokens')" = "10000" ] && ok || no "B sonnet cr"
[ "$(j '.dispatches.bbbb2222.models."claude-sonnet-5".cost_usd')" = "0.0555" ] && ok || no "B sonnet cost 0.0555 (intro+std)"

# Grand totals
[ "$(j '.totals.models."claude-opus-4-8".cost_usd')" = "0.061" ] && ok || no "total opus cost"
[ "$(j '.totals.models."claude-sonnet-5".cost_usd')" = "0.0555" ] && ok || no "total sonnet cost"
[ "$(j '.totals.cost_usd')" = "0.1165" ] && ok || no "grand cost 0.1165"
```

Note on float comparison: the token values were chosen so every per-model cost is exact at four decimals; jq prints `0.061`, `0.0555`, `0.1165` without trailing-float noise. If any assertion shows a value like `0.06100000000001`, the hook is accumulating in a way that introduces float error — fix by summing token counts as integers first and multiplying by rates once per class (see Step 3), not by summing per-request floats blindly. The chosen values avoid this entirely.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_cost_hook.sh`
Expected: FAIL — `.dispatches` is `{}` from the Task 3 skeleton.

- [ ] **Step 3: Implement dispatch parsing and pricing**

Replace the `# --- minimal for Task 3 ---` block in `hooks/agent-team-cost.sh` (from `printf '%s' "$(jq -n ...` through `exit 0`) with the parse-scan-price logic. Add a jq program that, for one dispatch file, dedups by `message.id`, sums the five token classes per model, prices each request by its timestamp against the rates, and emits the per-dispatch object. Rates are passed in with `--slurpfile`.

```bash
# Load rates; unreadable/invalid rates -> unavailable.
jq empty "$RATES" 2>/dev/null || write_unavailable "rates file $RATES is missing or not JSON"

# parse_dispatch FILE AGENT_TYPE -> prints the per-dispatch JSON object on stdout,
# or exits the whole hook via write_unavailable on any recognition failure.
# The jq program does all format-recognition, dedup, summation and pricing.
COST_PROG="$HERE/agent-team-cost.jq"   # NOTE: inline below via -f is avoided; program is embedded as a heredoc string.
```

Rather than a second file, embed the jq program as a bash variable and run it with `jq -n --rawfile`/`--slurpfile`. Concretely, add this function:

```bash
# Returns 0 and prints the dispatch JSON; returns 1 and prints a reason on failure.
parse_dispatch() { # $1 file, $2 agent_type
  local file="$1" atype="$2" size
  size="$(wc -c < "$file" | tr -d ' ')"
  # (a) every line must be a JSON object.
  local bad
  bad="$(jq -e . "$file" >/dev/null 2>&1; echo $?)"
  if [ "$bad" != "0" ]; then echo "unparseable line in $(basename "$file")"; return 1; fi
  # Feed the file (as a JSON array of its records) plus rates into one jq program.
  jq -n \
    --slurpfile recs <(jq -s '.' "$file") \
    --slurpfile rates "$RATES" \
    --arg atype "$atype" --arg file "$file" --argjson size "$size" '
    ($rates[0].models) as $M |
    ($recs[0]) as $R |
    # Assistant records that actually carry usage.
    [ $R[] | select(.type=="assistant" and (.message.usage != null)) ] as $U |
    # (b) shape recognition on each usage record.
    ( $U | map(
        (.message.id|type=="string") and
        (.message.model|type=="string" and (.|length>0)) and
        (.message.usage.input_tokens|type=="number") and
        (.message.usage.cache_creation_input_tokens|type=="number") and
        (.message.usage.cache_read_input_tokens|type=="number")
      ) | all ) as $shape_ok |
    if ($shape_ok|not) then {error:"malformed usage record shape"} else
    # Skip synthetic error model; strip trailing [1m].
    [ $U[] | .m = (.message.model | sub("\\[1m\\]$";"")) | select(.m != "<synthetic>") ] as $U2 |
    # (e) every model must be priceable.
    ( [ $U2[].m ] | unique ) as $models |
    if ([ $models[] | in($M) ] | all | not) then {error:"model not in rates config"} else
    # (c) within each message.id group, input & cache identical across snapshots.
    ( $U2 | group_by(.message.id) ) as $grp |
    ( $grp | map(
        (map(.message.usage.input_tokens)|unique|length==1) and
        (map(.message.usage.cache_creation_input_tokens)|unique|length==1) and
        (map(.message.usage.cache_read_input_tokens)|unique|length==1)
      ) | all ) as $dedup_ok |
    if ($dedup_ok|not) then {error:"snapshot input/cache mismatch within message id"} else
    # (d) when cache_creation present, 5m+1h == cache_creation_input_tokens.
    ( $U2 | map(select(.message.usage.cache_creation != null) |
        (.message.usage.cache_creation.ephemeral_5m_input_tokens + .message.usage.cache_creation.ephemeral_1h_input_tokens)
          == .message.usage.cache_creation_input_tokens
      ) | all ) as $split_ok |
    if ($split_ok|not) then {error:"cache_creation split does not sum to cache_creation_input_tokens"} else
    # One logical request per message.id: pick a representative (first) for
    # input/cache, take MAX output across the group.
    ( $grp | map({
        m: .[0].m,
        ts: .[0].timestamp,
        input:  .[0].message.usage.input_tokens,
        cread:  .[0].message.usage.cache_read_input_tokens,
        cw5m:   (if .[0].message.usage.cache_creation then .[0].message.usage.cache_creation.ephemeral_5m_input_tokens
                 else .[0].message.usage.cache_creation_input_tokens end),
        cw1h:   (if .[0].message.usage.cache_creation then .[0].message.usage.cache_creation.ephemeral_1h_input_tokens
                 else 0 end),
        output: (map(.message.usage.output_tokens // 0) | max)
      }) ) as $reqs |
    # Price each request by its date against std or intro rates.
    ( $reqs | map(
        ($M[.m]) as $mr |
        (if ($mr.intro != null) and (.ts[0:10] <= $mr.intro.ends) then $mr.intro else $mr end) as $r |
        . + { cost: ( (.input*$r.input + .output*$r.output + .cw5m*$r.cache_write_5m
                       + .cw1h*$r.cache_write_1h + .cread*$r.cache_read) / 1000000 ) }
      ) ) as $priced |
    # Aggregate per model.
    ( $priced | group_by(.m) | map({
        key: .[0].m,
        value: {
          input_tokens: (map(.input)|add),
          output_tokens: (map(.output)|add),
          cache_write_5m_tokens: (map(.cw5m)|add),
          cache_write_1h_tokens: (map(.cw1h)|add),
          cache_read_tokens: (map(.cread)|add),
          cost_usd: (map(.cost)|add)
        }
      }) | from_entries ) as $bymodel |
    # server_tool_use tallies (billed per use, counted not priced).
    ( [ $U[] | .message.usage.server_tool_use.web_search_requests // 0 ] | add // 0 ) as $ws |
    ( [ $U[] | .message.usage.server_tool_use.web_fetch_requests // 0 ] | add // 0 ) as $wf |
    { agent_type: $atype, file: $file, file_size: $size,
      requests: ($reqs|length), models: $bymodel,
      web_search_requests: $ws, web_fetch_requests: $wf }
    end end end end end
  '
}
```

Then replace the skeleton write with a scan-all-and-assemble loop:

```bash
# Start fresh dispatches map (Task 5 makes this incremental).
DISPATCHES='{}'
if [ -d "$SUBAGENTS_DIR" ]; then
  for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    aid="$(basename "$f")"; aid="${aid#agent-}"; aid="${aid%.jsonl}"
    atype="unknown"; [ "$aid" = "$AGENT_ID" ] && atype="$AGENT_TYPE"
    entry="$(parse_dispatch "$f" "$atype")" || write_unavailable "$(basename "$f"): $entry"
    if printf '%s' "$entry" | jq -e '.error' >/dev/null 2>&1; then
      write_unavailable "$(basename "$f"): $(printf '%s' "$entry" | jq -r .error)"
    fi
    DISPATCHES="$(jq -n --argjson d "$DISPATCHES" --arg k "$aid" --argjson v "$entry" '$d + {($k):$v}')"
  done
fi

# Roll up totals across all dispatch entries.
DOC="$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" --argjson d "$DISPATCHES" '
  ($d | [.[].models] ) as $allm |
  ([ $allm[] | to_entries[] ] | group_by(.key) | map({
     key: .[0].key,
     value: {
       input_tokens: (map(.value.input_tokens)|add),
       output_tokens: (map(.value.output_tokens)|add),
       cache_write_5m_tokens: (map(.value.cache_write_5m_tokens)|add),
       cache_write_1h_tokens: (map(.value.cache_write_1h_tokens)|add),
       cache_read_tokens: (map(.value.cache_read_tokens)|add),
       cost_usd: (map(.value.cost_usd)|add)
     }
   }) | from_entries) as $tm |
  { version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"ok",
    dispatches:$d,
    totals: {
      models: $tm,
      cost_usd: ([ $tm[].cost_usd ] | add // 0),
      web_search_requests: ([ $d[].web_search_requests ] | add // 0),
      web_fetch_requests: ([ $d[].web_fetch_requests ] | add // 0)
    } }')"
printf '%s' "$DOC" > "$COST_FILE"
exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_cost_hook.sh`
Expected: all Task 3 + Task 4 assertions pass; final line shows the new higher `passed=` count, `failed=0`.

- [ ] **Step 5: Confirm the file stays under 300 lines**

Run: `wc -l hooks/agent-team-cost.sh`
Expected: under 300. If over, the jq program is the bulk — it is a single cohesive routine and stays inline (splitting it into a sourced `.jq` file resolved from the script dir is acceptable if needed, but do not exceed 300 lines in the `.sh`).

- [ ] **Step 6: Commit**

```bash
git add hooks/agent-team-cost.sh tests/test_cost_hook.sh
git commit -m "feat: cost hook parses, dedups, and prices dispatch transcripts"
```

---

## Task 5: Incremental + idempotent (size-keyed re-parse)

**Files:**
- Modify: `hooks/agent-team-cost.sh`
- Modify: `tests/test_cost_hook.sh`

**Interfaces:**
- Consumes: `.dispatches["<id>"].file_size` from Task 4's schema.
- Produces: on each fire, load the prior cost file; for each dispatch file whose `file_size` matches the recorded entry, reuse the recorded entry unchanged (skip re-parse); re-parse only new or size-changed files and REPLACE that entry. Byte-identical output on an unchanged re-fire.

- [ ] **Step 1: Write the failing tests — idempotency and growth**

Add to `tests/test_cost_hook.sh`:

```bash
# --- Task 5: idempotent + incremental ---
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
FIRST="$(cat "$CF")"
run_hook "$(payload "$CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
SECOND="$(cat "$CF")"
# updated_at may differ; compare everything except updated_at.
a="$(printf '%s' "$FIRST"  | jq 'del(.updated_at)')"
b="$(printf '%s' "$SECOND" | jq 'del(.updated_at)')"
[ "$a" = "$b" ] && ok || no "re-fire is idempotent (totals unchanged)"

# Growth: copy the good tree into scratch, append a request to dispatch A, re-fire.
GROW="$SCRATCH/grow"
mkdir -p "$GROW/$SID/subagents"
cp "$FIXROOT/good/$SID.jsonl" "$GROW/$SID.jsonl"
cp "$FIXROOT/good/$SID/subagents/"agent-*.jsonl "$GROW/$SID/subagents/"
# Append one more opus request to A: input 1000, out 100, no cache -> cost 0.0075
cat >> "$GROW/$SID/subagents/agent-aaaa1111.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A3","uuid":"a3","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:02:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A3","type":"message","role":"assistant","usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}
EOF
GROW_CF="$(costfile_for "$CWD" "$SLUG" "$SID")"
run_hook "$(payload "$CWD" "$GROW/$SID.jsonl" "$SID" aaaa1111 architect)"
# A opus cost now 0.061 + 0.0075 = 0.0685; grand 0.1165 + 0.0075 = 0.124
[ "$(jq -r '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd' "$GROW_CF")" = "0.0685" ] && ok || no "growth updates dispatch A cost to 0.0685"
[ "$(jq -r '.dispatches.aaaa1111.requests' "$GROW_CF")" = "3" ] && ok || no "growth updates dispatch A requests to 3"
[ "$(jq -r '.totals.cost_usd' "$GROW_CF")" = "0.124" ] && ok || no "growth updates grand total to 0.124"
```

Note: the grow case reuses the same slug+sid, so it writes the same cost file the earlier cases used — that is fine because the growth fire re-derives from the grown tree. To avoid cross-test coupling on `file_size`, the growth fire points `transcript_path` at the grown tree, whose dispatch A file is larger than the fixture's, so the size-changed branch re-parses it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_cost_hook.sh`
Expected: the idempotency assertion may already pass (Task 4 re-derives fully each fire), but the growth assertions pass too since Task 4 has no caching yet. The purpose of Task 5 is to ADD size-keyed skipping without breaking these. If all Task 5 assertions already pass on the Task-4 hook, that is acceptable — proceed to Step 3 to add the incremental optimization and confirm it still passes. (Write the tests first regardless; they are the guard for Step 3.)

- [ ] **Step 3: Add size-keyed incremental reuse**

In `hooks/agent-team-cost.sh`, load the prior cost file and reuse unchanged entries. Replace `DISPATCHES='{}'` and the loop body's parse with:

```bash
# Load prior entries if the existing file is a valid "ok" doc; a sticky
# "unavailable" file is handled earlier (Task 6). Missing/invalid -> fresh.
PRIOR='{}'
if [ -f "$COST_FILE" ] && jq -e '.status=="ok"' "$COST_FILE" >/dev/null 2>&1; then
  PRIOR="$(jq -c '.dispatches // {}' "$COST_FILE")"
fi
DISPATCHES='{}'
if [ -d "$SUBAGENTS_DIR" ]; then
  for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    aid="$(basename "$f")"; aid="${aid#agent-}"; aid="${aid%.jsonl}"
    size="$(wc -c < "$f" | tr -d ' ')"
    prior_size="$(printf '%s' "$PRIOR" | jq -r --arg k "$aid" '.[$k].file_size // "none"')"
    if [ "$prior_size" = "$size" ]; then
      entry="$(printf '%s' "$PRIOR" | jq -c --arg k "$aid" '.[$k]')"   # reuse unchanged
    else
      atype="unknown"; [ "$aid" = "$AGENT_ID" ] && atype="$AGENT_TYPE"
      entry="$(parse_dispatch "$f" "$atype")" || write_unavailable "$(basename "$f"): $entry"
      if printf '%s' "$entry" | jq -e '.error' >/dev/null 2>&1; then
        write_unavailable "$(basename "$f"): $(printf '%s' "$entry" | jq -r .error)"
      fi
    fi
    DISPATCHES="$(jq -n --argjson d "$DISPATCHES" --arg k "$aid" --argjson v "$entry" '$d + {($k):$v}')"
  done
fi
```

The totals roll-up from Task 4 stays unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_cost_hook.sh`
Expected: all assertions pass, `failed=0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-cost.sh tests/test_cost_hook.sh
git commit -m "feat: size-keyed incremental re-parse (idempotent, self-healing)"
```

---

## Task 6: Unavailable marker — malformed, unknown model, sticky

**Files:**
- Modify: `hooks/agent-team-cost.sh`
- Modify: `tests/test_cost_hook.sh`

**Interfaces:**
- Consumes: `write_unavailable` (Task 3) and `parse_dispatch`'s `{error:...}`/non-JSON detection (Task 4).
- Produces: an early "sticky" check — if the existing cost file already has `status != "ok"`, leave it unavailable and exit 0 without re-scanning. This is Acceptance Criterion 2 and the sticky clause.

- [ ] **Step 1: Write the failing tests — malformed, unknown-model, sticky, exit 0**

Add to `tests/test_cost_hook.sh`:

```bash
# --- Task 6: unavailable marker ---
MAL_TP="$FIXROOT/malformed/$SID.jsonl"
MAL_CWD="/fake/mal"; MAL_SLUG="-fake-mal"
MAL_CF="$(costfile_for "$MAL_CWD" "$MAL_SLUG" "$SID")"
run_hook "$(payload "$MAL_CWD" "$MAL_TP" "$SID" cccc3333 researcher)"
[ "$RC" -eq 0 ] && ok || no "malformed fire exits 0"
[ "$(jq -r '.status' "$MAL_CF")" = "unavailable" ] && ok || no "malformed -> status unavailable"
[ -n "$(jq -r '.unavailable_reason // empty' "$MAL_CF")" ] && ok || no "malformed -> has a reason"

UNK_TP="$FIXROOT/unknown/$SID.jsonl"
UNK_CWD="/fake/unk"; UNK_SLUG="-fake-unk"
UNK_CF="$(costfile_for "$UNK_CWD" "$UNK_SLUG" "$SID")"
run_hook "$(payload "$UNK_CWD" "$UNK_TP" "$SID" dddd4444 verifier)"
[ "$RC" -eq 0 ] && ok || no "unknown-model fire exits 0"
[ "$(jq -r '.status' "$UNK_CF")" = "unavailable" ] && ok || no "unknown-model -> status unavailable"

# Sticky: after malformed, a fire over the GOOD tree at the SAME cost file stays unavailable.
run_hook "$(payload "$MAL_CWD" "$GOOD_TP" "$SID" aaaa1111 architect)"
[ "$(jq -r '.status' "$MAL_CF")" = "unavailable" ] && ok || no "unavailable is sticky for the session"
```

Note: the sticky case fires with `cwd=/fake/mal` (so it writes to `MAL_CF`, already unavailable) but a good `transcript_path`. Because the marker is sticky, the good data must NOT overwrite it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_cost_hook.sh`
Expected: FAIL — the malformed transcript trips `parse_dispatch`, but sticky is not yet enforced; the sticky assertion fails because the good fire overwrites the marker with `status:"ok"`.

- [ ] **Step 3: Add the sticky early-return**

In `hooks/agent-team-cost.sh`, immediately after computing `COST_FILE` and before any scanning, add:

```bash
# Sticky unavailable: once a session's totals can't be trusted, they stay that
# way. A prior non-ok status wins over any later good data.
if [ -f "$COST_FILE" ] && jq -e '.status? and (.status != "ok")' "$COST_FILE" >/dev/null 2>&1; then
  exit 0
fi
```

The malformed and unknown-model paths already write the marker via `parse_dispatch` returning non-zero / `{error:...}` (Task 4). Confirm the malformed detection (`jq -e . "$file"`) fires on a non-JSON line — it does, because `jq -e . file` fails when any line is not valid JSON.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_cost_hook.sh`
Expected: all assertions pass, `failed=0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-cost.sh tests/test_cost_hook.sh
git commit -m "feat: sticky unavailable marker on unrecognized transcripts"
```

---

## Task 7: Empty / missing subagents dir is a valid empty state

**Files:**
- Modify: `hooks/agent-team-cost.sh` (verify only — likely already correct)
- Modify: `tests/test_cost_hook.sh`

- [ ] **Step 1: Write the failing test — no subagents dir yields an ok empty doc**

Add to `tests/test_cost_hook.sh`:

```bash
# --- Task 7: empty state ---
EMPTY_CWD="/fake/empty"; EMPTY_SLUG="-fake-empty"
EMPTY_TP="$SCRATCH/empty/$SID.jsonl"   # no subagents dir exists alongside it
mkdir -p "$SCRATCH/empty"
printf '%s\n' '{"type":"user"}' > "$EMPTY_TP"
EMPTY_CF="$(costfile_for "$EMPTY_CWD" "$EMPTY_SLUG" "$SID")"
run_hook "$(payload "$EMPTY_CWD" "$EMPTY_TP" "$SID" eeee5555 scribe)"
[ "$RC" -eq 0 ] && ok || no "empty subagents dir exits 0"
[ "$(jq -r '.status' "$EMPTY_CF")" = "ok" ] && ok || no "empty subagents dir -> status ok"
[ "$(jq -r '.totals.cost_usd' "$EMPTY_CF")" = "0" ] && ok || no "empty subagents dir -> zero cost"
```

- [ ] **Step 2: Run the test**

Run: `bash tests/test_cost_hook.sh`
Expected: PASS if the Task 4/5 `[ -d "$SUBAGENTS_DIR" ]` guard already handles absence. If it FAILs (e.g. the glob `agent-*.jsonl` in a nonexistent dir errored under `set -u`), fix by keeping the `[ -e "$f" ] || continue` guard inside the `[ -d ... ]` block (already present). Confirm.

- [ ] **Step 3: Commit (only if the hook changed)**

```bash
git add tests/test_cost_hook.sh hooks/agent-team-cost.sh
git commit -m "test: empty subagents dir is a valid zero-cost ok state"
```

---

## Task 8: web-search / web-fetch counts carried, not priced

**Files:**
- Modify: `tests/test_cost_hook.sh`
- (Hook already tallies these in Task 4 — this task adds a fixture line and asserts the count surfaces without affecting cost.)

- [ ] **Step 1: Add a web-tool fixture and the failing test**

Append a request carrying `server_tool_use` counts to a scratch copy so the committed good fixture's hand math stays untouched:

```bash
# --- Task 8: server web-tool counts carried, not priced ---
WT="$SCRATCH/webtool"
mkdir -p "$WT/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$WT/$SID.jsonl"
cat > "$WT/$SID/subagents/agent-ffff6666.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"agentId":"ffff6666","requestId":"req_W1","uuid":"w1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_W1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10,"server_tool_use":{"web_search_requests":3,"web_fetch_requests":2}}}}
EOF
WT_CWD="/fake/wt"; WT_SLUG="-fake-wt"
WT_CF="$(costfile_for "$WT_CWD" "$WT_SLUG" "$SID")"
run_hook "$(payload "$WT_CWD" "$WT/$SID.jsonl" "$SID" ffff6666 researcher)"
[ "$(jq -r '.totals.web_search_requests' "$WT_CF")" = "3" ] && ok || no "web_search_requests carried = 3"
[ "$(jq -r '.totals.web_fetch_requests' "$WT_CF")" = "2" ] && ok || no "web_fetch_requests carried = 2"
# cost is token-only: (100*5 + 10*25)/1e6 = 750/1e6 = 0.00075, unaffected by web counts
[ "$(jq -r '.totals.cost_usd' "$WT_CF")" = "0.00075" ] && ok || no "web-tool request cost is token-only 0.00075"
```

- [ ] **Step 2: Run the test**

Run: `bash tests/test_cost_hook.sh`
Expected: PASS — the Task 4 hook already tallies `server_tool_use.web_search_requests`/`web_fetch_requests` and prices only tokens.

- [ ] **Step 3: Commit**

```bash
git add tests/test_cost_hook.sh
git commit -m "test: web-search/web-fetch counts carried, cost stays token-only"
```

---

## Task 9: Installer — validate + install the two new files (Component 6)

**Files:**
- Modify: `install.sh`

**Interfaces:**
- Consumes: `hooks/agent-team-cost.sh`, `hooks/model-rates.json`, `tests/test_cost_hook.sh`.
- Produces: validated install of both files into `~/.claude/hooks/`, with backup/restore/cleanup mirroring `PREEXISTING_POLICY*`, and the new suite added to the validation gate.

- [ ] **Step 1: Add validation of the new files (before anything is touched)**

In `install.sh`, after the existing policy-mutations `bash -n` line (line 28) and before the policy test run (line 29), add:

```bash
[ -f "$REPO/hooks/agent-team-cost.sh" ] || fail "hooks/agent-team-cost.sh is missing from repo"
[ -f "$REPO/hooks/model-rates.json" ] || fail "hooks/model-rates.json is missing from repo"
bash -n "$REPO/hooks/agent-team-cost.sh" || fail "cost hook failed bash -n"
jq empty "$REPO/hooks/model-rates.json" || fail "model-rates.json is not valid JSON"
jq -e '[.models[] | [.input,.output,.cache_write_5m,.cache_write_1h,.cache_read] | all(type=="number")] | all' \
  "$REPO/hooks/model-rates.json" >/dev/null \
  || fail "model-rates.json: every model must carry five numeric rate keys"
```

Then, after the existing policy-test line (line 29), add:

```bash
bash "$REPO/tests/test_cost_hook.sh" >/dev/null || fail "cost hook tests failed — run tests/test_cost_hook.sh to see which"
```

- [ ] **Step 2: Add backup tracking for the two new files**

After the `PREEXISTING_POLICY_MUT=0` block (around line 146), add:

```bash
PREEXISTING_COST=0
PREEXISTING_RATES=0
[ -f "$CLAUDE_DIR/hooks/agent-team-cost.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-cost.sh" "$BACKUP/"; PREEXISTING_COST=1; }
[ -f "$CLAUDE_DIR/hooks/model-rates.json" ] && { cp "$CLAUDE_DIR/hooks/model-rates.json" "$BACKUP/"; PREEXISTING_RATES=1; }
```

- [ ] **Step 3: Extend restore() and cleanup_fresh() for the two new files**

In `restore()`, add two cases inside the `case "$(basename "$b")"` block:

```bash
      agent-team-cost.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      model-rates.json) cp "$b" "$CLAUDE_DIR/hooks/" ;;
```

In `cleanup_fresh()`, after the existing `PREEXISTING_POLICY_MUT` line, add:

```bash
  [ "$PREEXISTING_COST" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-cost.sh"
  [ "$PREEXISTING_RATES" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/model-rates.json"
```

- [ ] **Step 4: Add the install copy steps**

After the existing `agent-team-policy-mutations.sh` copy line (around line 183), add:

```bash
if ! cp "$REPO/hooks/agent-team-cost.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "cost hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/model-rates.json" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "rates file copy failed; rolled back"; fi
```

After the existing `chmod +x ...agent-team-policy.sh` line (line 188), add (the rates file is read-only, only the script is chmod'd):

```bash
chmod +x "$CLAUDE_DIR/hooks/agent-team-cost.sh" || { restore; cleanup_fresh; fail "chmod of cost hook failed; rolled back"; }
```

- [ ] **Step 5: Add the two files to the manifest's HOOK_FILES**

Change line 20 from:

```bash
HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh"
```

to:

```bash
HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh agent-team-cost.sh model-rates.json"
```

This makes `install.sh --check` track both new files for drift, symmetric with the policy files.

- [ ] **Step 6: Update the success message count**

Change the final `echo "install: OK — 10 agents installed, policy hook installed, ..."` to also mention the cost hook:

```bash
echo "install: OK — 10 agents installed, policy hook + cost hook installed, build $COMMIT recorded, backup at $BACKUP"
```

- [ ] **Step 7: Validate and run the installer**

Run:
```bash
bash -n install.sh && bash install.sh
```
Expected: `bash -n` clean; installer prints `install: OK — ...`, having run both test suites during validation. Then confirm drift check is clean:
```bash
bash install.sh --check
```
Expected: `check: OK — ...`.

- [ ] **Step 8: Commit**

```bash
git add install.sh
git commit -m "feat: install validates + ships cost hook and rates file"
```

---

## Task 10: Orchestrator closeout — two-path procedure + frontmatter hook (Component 4)

**Files:**
- Modify: `agents/orchestrator.md` (frontmatter; the "Closeout cost report" section)

**Interfaces:**
- Consumes: the cost-file schema (Task 4) at `~/.claude/logs/agent-team-cost/<slug>--<sid>.json`.

- [ ] **Step 1: Add the PostToolUse hook to the frontmatter**

In `agents/orchestrator.md`, the frontmatter currently ends at line 6 (`tools: ...`) with `---` on line 7. Add a `hooks:` block before the closing `---`. Edit the closing delimiter region:

Replace:
```
tools: Read, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, Agent(architect), Agent(builder), Agent(verifier), Agent(reviewer), Agent(deployer), Agent(researcher), Agent(ops), Agent(scribe), Agent(ticketer)
---
```
with:
```
tools: Read, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, Agent(architect), Agent(builder), Agent(verifier), Agent(reviewer), Agent(deployer), Agent(researcher), Agent(ops), Agent(scribe), Agent(ticketer)
hooks:
  PostToolUse:
    - matcher: Agent
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-cost.sh"
---
```

- [ ] **Step 2: Rewrite the Closeout cost report section (keep the blended table as fallback)**

Replace the current section body (lines 74–85, from "Dispatch specialists in the background" through the "n/a" sentence) — keeping the `## Closeout cost report` heading — with the two-path procedure. Preserve the existing blended-rate table verbatim as the fallback:

```markdown
Two-path procedure, evaluated at the FINAL gate only (not intermediate gates).

**Exact path (preferred).** A PostToolUse hook records exact per-request token usage — input, output, cache-write, and cache-read, attributed to each model — into a per-session cost file as each dispatch completes. To use it: Glob `$HOME/.claude/logs/agent-team-cost/<your-cwd-with-slashes-as-dashes>--*.json` (slug your own working directory by replacing every `/` with `-`), Read the most recently modified match, and if it parses and its `status` is `"ok"`, emit the EXACT table: one row per model with input, output, cache-write (5m + 1h combined), and cache-read token totals, plus that model's cost rounded to the cent; a grand-total row; and — from the per-dispatch tracking you already keep from completion notifications — the per-dispatch agent/model attribution. Label it plainly: exact per-request figures from the session transcripts, priced at list rates from `model-rates.json`; it excludes your own session usage (that stays `/usage`). If the cost file reports any nonzero `web_search_requests` or `web_fetch_requests`, add a footnote that those server-tool calls are billed per use and are counted but not priced here. Round for display half away from zero to two decimals.

**Fallback path.** If no cost file matches, the file does not parse, or its `status` is not `"ok"`, emit the blended-estimate table below instead, with its existing estimate labeling. Record agent, model, and tokens per dispatch as you go from each completion notification's usage block; estimate cost per dispatch as tokens × the model's blended rate, and label the result plainly as an estimate that excludes your own session usage and cache discounts — the human's exact number lives in /usage. If a dispatch ran foreground and you have no token count for it, show it as a row with "n/a" rather than inventing a number.

Blended rates (per million tokens, assumes agentic work is ~85% input-priced / 15% output-priced; raw list prices as of 2026-07, edit here when prices change):

| Model | Input / Output list | Blended estimate |
|---|---|---|
| haiku | $1 / $5 | ~$1.60/M |
| sonnet | $3 / $15 (intro $2/$10 through 2026-08-31) | ~$4.80/M (~$3.20/M intro) |
| opus | $5 / $25 | ~$8/M |
| fable | $10 / $50 | ~$16/M |

Known limitation: two concurrent orchestrator sessions in the same project directory share the Glob pattern; the most recently modified cost file wins.
```

- [ ] **Step 3: Reinstall so the edited orchestrator ships**

Run: `bash install.sh`
Expected: `install: OK`. (The agent-copy loop ships `orchestrator.md` automatically; no installer change needed for it.)

- [ ] **Step 4: Commit**

```bash
git add agents/orchestrator.md
git commit -m "feat: orchestrator prefers exact cost file, falls back to blended estimate"
```

---

## Task 11: README updates (Component / Files-to-change)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the install validation list**

In the `## How to install` bullet list, extend the hook-files and test bullets. Replace the bullet beginning "All three hook files" so it also names the cost hook and rates file, and add the cost-hook test to the test-suite bullet. Edit the "All three hook files ... pass `bash -n` syntax checks." bullet to read "All hook scripts — the three policy files plus `hooks/agent-team-cost.sh` (the PostToolUse cost-accounting hook) — pass `bash -n` syntax checks, and `hooks/model-rates.json` parses as JSON with the five numeric rate keys on every model." Then edit the test bullet "The full policy test suite (`tests/test_policy_hooks.sh`) passes." to "The full policy test suite (`tests/test_policy_hooks.sh`) and the cost-hook test suite (`tests/test_cost_hook.sh`) both pass."

- [ ] **Step 2: Update the final-gate cost description in "How to use"**

In the paragraph at lines 112–115 ("The final gate additionally includes a per-dispatch accounting table ..."), replace it to describe the two-path behavior:

```markdown
At the final gate, the orchestrator reports cost. When the per-session cost file
produced by the cost-accounting hook is present and valid, it reports the EXACT
per-model figures — input, output, cache-write, and cache-read tokens with cost
rounded to the cent — read straight from the session transcripts and priced at
list rates from `hooks/model-rates.json`. When that file is absent or the hook
marked it unavailable, it falls back to a blended per-dispatch ESTIMATE clearly
labeled as such. Either way the number excludes the orchestrator's own session
usage; your exact session-wide number is always `/usage`. Nonzero web-search or
web-fetch server-tool calls are counted and footnoted, not priced.
```

- [ ] **Step 3: Add a "Cost accounting" section**

Add a new `## Cost accounting` section (place it just before `## Shakedown checklist`):

```markdown
## Cost accounting

The orchestrator registers a `PostToolUse` hook, `hooks/agent-team-cost.sh`, that
fires after each dispatch completes. It reads exact per-request token usage from
the session's per-dispatch transcript files and writes a per-session cost file to
`~/.claude/logs/agent-team-cost/<project-slug>--<session-id>.json` (override the
directory with `AGENT_TEAM_COST_DIR`, and the rates file with `AGENT_TEAM_RATES`,
mainly for tests). Prices come only from `hooks/model-rates.json` — all list
prices per million tokens; the script contains no numbers. To change a rate, edit
that file and re-run `bash install.sh`.

The hook never emits a wrong number: if it cannot recognize a transcript's format,
or sees a model missing from the rates file, it writes a sticky "unavailable"
marker for that session and the orchestrator falls back to its blended estimate.
Cache-write is split into 5-minute and 1-hour tiers (they price differently);
server web-search/web-fetch calls are counted but not priced. Known limitation:
two orchestrator sessions running in the same directory at once share the cost-file
name pattern, and the most recently modified file wins.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README covers exact cost accounting and the two-path closeout"
```

---

## Task 12: Spec status updates (Files-to-change)

**Files:**
- Modify: `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md` (status line)
- Modify: `docs/superpowers/specs/2026-07-07-ai-agent-team-design.md` (dated amendment note in two places)

- [ ] **Step 1: Flip this spec's status**

In `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md`, change the status line from `**Status:** Proposed (standard tier; implementation plan is a separate later dispatch)` to `**Status:** Accepted 2026-07-08; implemented per docs/superpowers/plans/2026-07-08-exact-closeout-cost-accounting.md`.

- [ ] **Step 2: Amend the parent spec — Closeout cost report section**

Open `docs/superpowers/specs/2026-07-07-ai-agent-team-design.md`. Find the "Closeout cost report" text and the "Scope — v1" deferred item that reads "exact per-session cost accounting ... the closeout's estimate table is the shipped v1". Add, immediately after each, a dated amendment note:

For the Closeout section, append:
```markdown

> **Amendment 2026-07-08:** Exact per-session cost accounting has shipped. The closeout now
> prefers an exact per-model table read from a per-session cost file (produced by the
> `hooks/agent-team-cost.sh` PostToolUse hook), falling back to the blended-estimate table
> described here when that file is absent or unavailable. See
> `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md`.
```

For the deferred Scope item, append:
```markdown

> **Amendment 2026-07-08:** No longer deferred — shipped. See
> `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md`.
```

(Use Grep to find the exact surrounding text in that file first, then Edit with the exact old_string. If either phrase's wording differs from the spec's quotation, anchor on the actual on-disk text.)

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-07-ai-agent-team-design.md docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md
git commit -m "docs: mark exact cost accounting shipped in both specs"
```

---

## Task 13: Full acceptance run (all criteria)

**Files:** none created — verification only.

- [ ] **Step 1: Run the cost-hook suite**

Run: `bash tests/test_cost_hook.sh`
Expected: `failed=0`, exit 0. This covers Acceptance Criteria 1 (exact math to the cent over the good fixture), 2 (malformed + unknown-model → sticky unavailable, exit 0), and 3 (idempotent + incremental).

- [ ] **Step 2: Run the policy suite (regression — Component 5 case 7)**

Run: `bash tests/test_policy_hooks.sh`
Expected: `failed=0`, exit 0 — the pre-existing suite is untouched.

- [ ] **Step 3: Run the installer end-to-end (Acceptance Criterion 4)**

Run: `bash install.sh && bash install.sh --check`
Expected: `install: OK — ... policy hook + cost hook installed ...` then `check: OK — ...`. The installer having succeeded means both suites passed inside its validation gate.

- [ ] **Step 4: Confirm the graceful-fallback wording (Acceptance Criterion 5)**

Run: `grep -n "Fallback path" agents/orchestrator.md`
Expected: the fallback clause is present. A session where the hook never ran leaves no cost file, so the Glob finds nothing and the orchestrator's fallback path emits the blended-estimate table. (Live confirmation happens in the next shakedown, per the spec.)

- [ ] **Step 5: Confirm no file exceeds 300 lines and no deletion/move was authored**

Run:
```bash
wc -l hooks/agent-team-cost.sh tests/test_cost_hook.sh
grep -nE '(^|[^-])\b(rm|mv)\b' hooks/agent-team-cost.sh || echo "cost hook: no rm/mv (expected)"
```
Expected: both files under 300 lines; the cost hook contains no `rm`/`mv`.

- [ ] **Step 6: Final commit if anything changed during acceptance**

```bash
git status
# if clean, nothing to do; otherwise:
git add -A && git commit -m "chore: acceptance run for exact cost accounting"
```

---

## Task 14: Partial-read is transient — skip this fire, do not go sticky (Amendment 2026-07-09)

This is the core correctness fix. A sibling dispatch file that is **0-byte** or whose **final line is an unterminated/unparseable tail while every preceding line parses** is treated as *still being written*: it is skipped this fire (not counted, no sticky marker), so a later fire picks it up once flushing completes. Every other parse failure stays sticky-unavailable, exactly as today.

**Files:**
- Create: `tests/fixtures/cost/partial/<SID>/subagents/agent-aaaa1111.jsonl` (good, complete — same content as the good opus dispatch)
- Create: `tests/fixtures/cost/partial/<SID>/subagents/agent-9999pppp.jsonl` (a valid line + a truncated, unterminated final line)
- Create: `tests/fixtures/cost/partial/<SID>.jsonl` (main transcript stub)
- Modify: `hooks/agent-team-cost.sh`
- Modify: `tests/test_cost_hook.sh`

**Interfaces:**
- Consumes: `parse_dispatch` (Task 4), `write_unavailable` (Task 3), the scan loop (Task 5).
- Produces: a new hook helper `is_transient_partial FILE` → exit 0 if the file is a transient partial (0-byte, OR non-empty with an unterminated/unparseable final line and all preceding lines valid JSON objects), exit 1 otherwise. The scan loop `continue`s (skips) transient files without adding an entry or writing the marker.

- [ ] **Step 1: Create the partial fixtures**

Create `tests/fixtures/cost/partial/11111111-2222-3333-4444-555555555555.jsonl`:

```json
{"type":"user","uuid":"u1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T00:00:00.000Z"}
```

Create the complete-and-good sibling `tests/fixtures/cost/partial/11111111-2222-3333-4444-555555555555/subagents/agent-aaaa1111.jsonl` — identical content to the good opus dispatch (Task 2 Step 2), so it prices to opus cost 0.061:

```json
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A1","uuid":"a1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A1","type":"message","role":"assistant","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":4000,"cache_creation":{"ephemeral_5m_input_tokens":2000,"ephemeral_1h_input_tokens":0},"output_tokens":500}}}
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A2","uuid":"a2a","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:01:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A2","type":"message","role":"assistant","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":100}}}
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A2","uuid":"a2b","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:01:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A2","type":"message","role":"assistant","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":300}}}
{"type":"assistant","isSidechain":true,"agentId":"aaaa1111","requestId":"req_A2","uuid":"a2c","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:01:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_A2","type":"message","role":"assistant","usage":{"input_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":600}}}
```

Create the mid-write sibling `tests/fixtures/cost/partial/11111111-2222-3333-4444-555555555555/subagents/agent-9999pppp.jsonl` — one complete valid JSON line, then a truncated final line that is NOT newline-terminated and does NOT parse (a JSON object cut off mid-write). Write it so the last byte is not a newline. Use `printf` so no trailing newline is added:

```bash
mkdir -p tests/fixtures/cost/partial/11111111-2222-3333-4444-555555555555/subagents
printf '%s\n%s' \
  '{"type":"assistant","isSidechain":true,"agentId":"9999pppp","requestId":"req_P1","uuid":"p1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_P1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}' \
  '{"type":"assistant","isSidechain":true,"agentId":"9999pppp","requestId":"req_P2","uuid":"p2","message":{"model":"claude-opus-4-8","id":"msg_P2","usage":{"input_tokens":50,"cache_cre' \
  > tests/fixtures/cost/partial/11111111-2222-3333-4444-555555555555/subagents/agent-9999pppp.jsonl
```

(The final line is a genuine truncated tail: valid JSON prefix, cut off mid-key. It must not parse; the preceding line must parse.)

- [ ] **Step 2: Write the failing tests — partial sibling is skipped, good sibling still priced, no sticky**

Add to `tests/test_cost_hook.sh`, before the `echo "passed=..."` line:

```bash
# --- Task 14: transient partial-read is skipped, not sticky (Amendment 2026-07-09) ---
PART_TP="$FIXROOT/partial/$SID.jsonl"
PART_CWD="/fake/part"; PART_SLUG="-fake-part"
PART_CF="$(costfile_for "$PART_CWD" "$PART_SLUG" "$SID")"
run_hook "$(payload "$PART_CWD" "$PART_TP" "$SID" aaaa1111 architect)"
[ "$RC" -eq 0 ] && ok || no "partial fire exits 0"
# The truncated sibling must NOT flip the session to unavailable.
[ "$(jq -r '.status' "$PART_CF")" = "ok" ] && ok || no "partial sibling does NOT go sticky-unavailable"
# The good sibling is still priced.
[ "$(jq -r '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd' "$PART_CF")" = "0.061" ] && ok || no "good sibling still prices to 0.061 despite partial neighbor"
# The partial sibling contributes NO entry this fire (picked up later once complete).
[ "$(jq -r '.dispatches | has("9999pppp")' "$PART_CF")" = "false" ] && ok || no "partial sibling has no entry this fire"

# Once the partial file finishes flushing (becomes valid), a LATER fire folds it in.
GROWP="$SCRATCH/growpart"
mkdir -p "$GROWP/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$GROWP/$SID.jsonl"
cp "$FIXROOT/partial/$SID/subagents/agent-aaaa1111.jsonl" "$GROWP/$SID/subagents/"
# The completed version of 9999pppp: the truncated tail is now a valid, newline-terminated line.
printf '%s\n%s\n' \
  '{"type":"assistant","isSidechain":true,"agentId":"9999pppp","requestId":"req_P1","uuid":"p1","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:00.000Z","message":{"model":"claude-opus-4-8","id":"msg_P1","type":"message","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}' \
  '{"type":"assistant","isSidechain":true,"agentId":"9999pppp","requestId":"req_P2","uuid":"p2","sessionId":"11111111-2222-3333-4444-555555555555","timestamp":"2026-07-08T10:00:01.000Z","message":{"model":"claude-opus-4-8","id":"msg_P2","type":"message","role":"assistant","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}' \
  > "$GROWP/$SID/subagents/agent-9999pppp.jsonl"
GROWP_CF="$(costfile_for "$PART_CWD" "$PART_SLUG" "$SID")"
run_hook "$(payload "$PART_CWD" "$GROWP/$SID.jsonl" "$SID" 9999pppp researcher)"
[ "$(jq -r '.status' "$GROWP_CF")" = "ok" ] && ok || no "later fire stays ok after partial completes"
[ "$(jq -r '.dispatches | has("9999pppp")' "$GROWP_CF")" = "true" ] && ok || no "completed partial IS folded in on later fire (self-heal)"
# 9999pppp cost = P1 (100*5+10*25)/1e6=0.00075 + P2 (50*5+5*25)/1e6=0.000375 = 0.001125
[ "$(jq -r '.dispatches."9999pppp".models."claude-opus-4-8".cost_usd' "$GROWP_CF")" = "0.001125" ] && ok || no "completed partial prices to 0.001125"

# 0-byte sibling alongside a good one: skipped, good one still priced, not sticky.
ZERO="$SCRATCH/zero"
mkdir -p "$ZERO/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$ZERO/$SID.jsonl"
cp "$FIXROOT/partial/$SID/subagents/agent-aaaa1111.jsonl" "$ZERO/$SID/subagents/"
: > "$ZERO/$SID/subagents/agent-0000zzzz.jsonl"   # 0-byte sibling
ZERO_CWD="/fake/zero"; ZERO_SLUG="-fake-zero"
ZERO_CF="$(costfile_for "$ZERO_CWD" "$ZERO_SLUG" "$SID")"
run_hook "$(payload "$ZERO_CWD" "$ZERO/$SID.jsonl" "$SID" aaaa1111 architect)"
[ "$(jq -r '.status' "$ZERO_CF")" = "ok" ] && ok || no "0-byte sibling does NOT go sticky"
[ "$(jq -r '.dispatches.aaaa1111.models."claude-opus-4-8".cost_usd' "$ZERO_CF")" = "0.061" ] && ok || no "0-byte sibling: good dispatch still priced"
[ "$(jq -r '.dispatches | has("0000zzzz")' "$ZERO_CF")" = "false" ] && ok || no "0-byte sibling has no entry this fire"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test_cost_hook.sh`
Expected: FAIL — the current hook whole-file-parses `agent-9999pppp.jsonl`, fails on the truncated tail, and calls `write_unavailable`, so `.status` is `"unavailable"` (not `"ok"`) and the good sibling is lost. The 0-byte case likewise fails recognition today.

- [ ] **Step 4: Add the `is_transient_partial` helper and skip transient files in the scan loop**

In `hooks/agent-team-cost.sh`, add this helper immediately BEFORE `parse_dispatch()` (after the `write_unavailable` / rates-load block):

```bash
# is_transient_partial FILE -> exit 0 if the file looks like it is still being
# written (so it must be SKIPPED this fire and left for a later fire), exit 1
# otherwise. Two transient signatures (Amendment 2026-07-09, spec Component 1
# step 5): a 0-byte file; OR a non-empty file whose FINAL line fails to parse as
# JSON while EVERY preceding line parses as a JSON object (the mid-write tail).
# Any other parse failure is a genuine unrecognizable file (handled by
# parse_dispatch -> write_unavailable), not transient.
is_transient_partial() { # $1 file
  local file="$1"
  [ -s "$file" ] || return 0                      # 0-byte -> transient
  # If the whole file already parses, it is not partial.
  if jq -e . "$file" >/dev/null 2>&1; then return 1; fi
  # File has a parse failure somewhere. Transient only if it is confined to an
  # unterminated final line: all-but-last lines parse AND the last line does not.
  local total head_ok last_ok
  total="$(wc -l < "$file" | tr -d ' ')"          # count of NEWLINE chars
  # An unterminated tail means the byte stream does not end in a newline; the
  # "extra" trailing content is the (total+1)-th logical line. Validate the
  # first $total physical lines as a group, then the trailing remainder alone.
  head_ok=1; last_ok=1
  if [ "$total" -gt 0 ]; then
    head -n "$total" "$file" | jq -e . >/dev/null 2>&1 || head_ok=0
  fi
  # The trailing remainder after the last newline (empty if file ends in \n).
  tail -c +"$(( $(head -n "$total" "$file" | wc -c) + 1 ))" "$file" | jq -e . >/dev/null 2>&1 || last_ok=0
  # Transient iff the head parses cleanly and only the trailing remainder is bad.
  [ "$head_ok" -eq 1 ] && [ "$last_ok" -eq 0 ] && return 0
  return 1
}
```

Then, in the scan loop, add the transient check as the FIRST thing inside the `for f` body, before the size read:

```bash
  for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    if is_transient_partial "$f"; then continue; fi   # still being written -> skip this fire
    aid="$(basename "$f")"; aid="${aid#agent-}"; aid="${aid%.jsonl}"
    size="$(wc -c < "$f" | tr -d ' ')"
    ...
```

(Leave the rest of the loop body — the size-keyed reuse and `parse_dispatch` call — unchanged. A skipped file simply gets no entry this fire; a later fire, once the file is complete, runs the full path.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test_cost_hook.sh`
Expected: all assertions pass, `failed=0`. The truncated and 0-byte siblings are skipped (no sticky), the good sibling prices to 0.061, and the completed-later fire folds `9999pppp` in at 0.001125.

- [ ] **Step 6: Confirm a genuine mid-file corruption is STILL sticky (regression guard)**

Important boundary note. The committed malformed fixture (`tests/fixtures/cost/malformed/.../agent-cccc3333.jsonl`) has a valid line 1, a bad line 2, AND a trailing newline. Under `is_transient_partial` that is NOT transient: `wc -l` counts 2 newlines, the `head -n 2` group includes the bad line so the head fails to parse (`head_ok=0`), and the function returns 1 → `parse_dispatch` → `write_unavailable`. So Task 6's malformed case (status unavailable) still holds unchanged — DO NOT "fix" it to sticky by hand; verify Task 6 still passes.

Accepted ambiguity (spec §D7 Amendment 2026-07-09): an unterminated final bad line with NO trailing newline IS classified transient — that is the intended behavior, because it is indistinguishable from a mid-flush truncation and the trade is "missing, never wrong" (see the spec). Do not add code to disambiguate it; a truly corrupt no-newline tail that never completes is simply never counted.

To make the still-sticky intent explicit for the unambiguous case, add one assertion that a bad line FOLLOWED by a good line still goes sticky:

Add to `tests/test_cost_hook.sh`:

```bash
# A bad line in the MIDDLE (good line after it) is genuine corruption -> sticky.
MIDBAD="$SCRATCH/midbad"
mkdir -p "$MIDBAD/$SID/subagents"
printf '%s\n' '{"type":"user"}' > "$MIDBAD/$SID.jsonl"
printf '%s\n%s\n%s\n' \
  '{"type":"assistant","isSidechain":true,"agentId":"7777mmmm","message":{"model":"claude-opus-4-8","id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}' \
  'not json at all {{{' \
  '{"type":"assistant","isSidechain":true,"agentId":"7777mmmm","message":{"model":"claude-opus-4-8","id":"m2","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}' \
  > "$MIDBAD/$SID/subagents/agent-7777mmmm.jsonl"
MIDBAD_CWD="/fake/midbad"; MIDBAD_SLUG="-fake-midbad"
MIDBAD_CF="$(costfile_for "$MIDBAD_CWD" "$MIDBAD_SLUG" "$SID")"
run_hook "$(payload "$MIDBAD_CWD" "$MIDBAD/$SID.jsonl" "$SID" 7777mmmm researcher)"
[ "$(jq -r '.status' "$MIDBAD_CF")" = "unavailable" ] && ok || no "bad line in middle stays genuine -> unavailable"
```

Run: `bash tests/test_cost_hook.sh`
Expected: PASS — `is_transient_partial` returns 1 for this file (the bad line is not the sole trailing remainder; the head-of-file group including the bad middle line fails to parse), so `parse_dispatch` runs and `write_unavailable` fires as before.

- [ ] **Step 7: Confirm the file stays under 300 lines**

Run: `wc -l hooks/agent-team-cost.sh`
Expected: under 300.

- [ ] **Step 8: Commit**

```bash
git add hooks/agent-team-cost.sh tests/test_cost_hook.sh tests/fixtures/cost/partial
git commit -m "fix: transient partial-read sibling is skipped, not sticky (self-heal)"
```

---

## Task 15: Fix the `parse_dispatch` comment — stdout, not stderr (Amendment 2026-07-09, nit 1)

The header comment on `parse_dispatch` says failures print the reason "on stderr". The code prints the reason on **stdout** (via `echo`), and the scan loop relies on capturing it there. The code is correct; only the comment is wrong.

**Files:**
- Modify: `hooks/agent-team-cost.sh`

- [ ] **Step 1: Correct the comment**

In `hooks/agent-team-cost.sh`, replace the `parse_dispatch` header comment phrase:

```
# stdout on success, or a one-line reason on stderr and a non-zero exit on any
```
with:
```
# stdout on success, or a one-line reason on stdout and a non-zero exit on any
```

(No code change. The scan loop captures the reason via `entry="$(parse_dispatch …)"`, which reads stdout — the existing behavior is correct.)

- [ ] **Step 2: Verify the suite still passes (comment-only change)**

Run: `bash tests/test_cost_hook.sh`
Expected: `failed=0` — behavior unchanged.

- [ ] **Step 3: Commit**

```bash
git add hooks/agent-team-cost.sh
git commit -m "docs: correct parse_dispatch comment (reason prints on stdout)"
```

---

## Task 16: Installer rate-precision guard + UUID session_id check (Amendment 2026-07-09, nits 2 & 3)

Two defense-in-depth additions: fail the installer if any rate carries more than 4 fractional decimal digits (protects the `nofloat` 10-decimal snap), and reject a non-UUID `session_id` in the hook before building the cost-file path.

**Files:**
- Modify: `install.sh`
- Modify: `hooks/agent-team-cost.sh`
- Modify: `tests/test_cost_hook.sh`

**Interfaces:**
- Produces (hook): a UUID-shape guard on `session_id` — non-UUID ⇒ write nothing, exit 0.
- Produces (installer): the existing `jq -e` rate-shape check is extended with a fractional-digit bound.

- [ ] **Step 1: Write the failing test — non-UUID session_id writes nothing**

Add to `tests/test_cost_hook.sh`:

```bash
# --- Task 16: non-UUID session_id is rejected (path confinement) ---
BADSID_CWD="/fake/badsid"; BADSID_SLUG="-fake-badsid"
BADSID="../../etc/evil"                       # not a UUID; would escape the dir
BADSID_CF="$AGENT_TEAM_COST_DIR/$BADSID_SLUG--$BADSID.json"
run_hook "$(payload "$BADSID_CWD" "$GOOD_TP" "$BADSID" aaaa1111 architect)"
[ "$RC" -eq 0 ] && ok || no "non-UUID session_id exits 0"
[ ! -f "$BADSID_CF" ] && ok || no "non-UUID session_id writes nothing"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_cost_hook.sh`
Expected: FAIL — the current hook builds the path from any non-empty `session_id` and writes a file.

- [ ] **Step 3: Add the UUID guard to the hook**

In `hooks/agent-team-cost.sh`, immediately after the existing `[ -n "$TRANSCRIPT" ] || exit 0` line, add:

```bash
# Path-confinement defense (Amendment 2026-07-09): session_id must be a UUID
# before it is used to build the cost-file name. Claude Code always supplies one.
case "$SESSION_ID" in
  [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) : ;;
  *) exit 0 ;;
esac
```

(A `case` glob is used rather than a regex to avoid a `[[ =~ ]]` bashism dependency; the pattern is the exact 8-4-4-4-12 hex UUID shape. It runs before `COST_FILE` is constructed.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_cost_hook.sh`
Expected: `failed=0` — the non-UUID payload now exits 0 and writes nothing; the existing fixtures all use the valid UUID `11111111-2222-3333-4444-555555555555` and still pass.

- [ ] **Step 5: Extend the installer rate-shape check with a fractional-digit bound**

In `install.sh`, replace the existing rate-shape check (the `jq -e '[.models[] | [.input,...] | all(type=="number")] | all'` block, currently at lines 33–35) with a version that also bounds fractional precision. Include the `intro` rates in the scan:

```bash
jq -e '
  def rates: [ .input, .output, .cache_write_5m, .cache_write_1h, .cache_read ];
  def entries: [ .models[], ( .models[].intro | select(. != null) ) ];
  ([ entries[] | rates[] | type == "number" ] | all)
  and
  # No rate may carry more than 4 fractional decimal digits: r*10000 must be an
  # integer. Protects the hook nofloat 10-decimal snap invariant.
  ([ entries[] | rates[] | (. * 10000) | (. == (. | floor)) ] | all)
' "$REPO/hooks/model-rates.json" >/dev/null \
  || fail "model-rates.json: every model needs five numeric rate keys, each with at most 4 fractional decimal digits"
```

- [ ] **Step 6: Verify the installer accepts the current rates and rejects an over-precise one**

Run:
```bash
bash -n install.sh
jq -e '
  def rates: [ .input, .output, .cache_write_5m, .cache_write_1h, .cache_read ];
  def entries: [ .models[], ( .models[].intro | select(. != null) ) ];
  ([ entries[] | rates[] | type == "number" ] | all)
  and ([ entries[] | rates[] | (. * 10000) | (. == (. | floor)) ] | all)
' hooks/model-rates.json
```
Expected: `bash -n` clean; the jq check prints `true` (all current rates have ≤2 decimals). To confirm the guard bites, run the same jq program against a temporary over-precise value:
```bash
jq '.models."claude-opus-4-8".input = 5.12345' hooks/model-rates.json | jq -e '
  def rates: [ .input, .output, .cache_write_5m, .cache_write_1h, .cache_read ];
  def entries: [ .models[], ( .models[].intro | select(. != null) ) ];
  ([ entries[] | rates[] | (. * 10000) | (. == (. | floor)) ] | all)'
```
Expected: prints `false` (5-decimal rate rejected). This is a manual confirmation, not a committed fixture — do not write the over-precise value to any file.

- [ ] **Step 7: Run the installer end-to-end**

Run: `bash install.sh && bash install.sh --check`
Expected: `install: OK — ...` then `check: OK — ...`; both test suites pass inside the validation gate.

- [ ] **Step 8: Commit**

```bash
git add install.sh hooks/agent-team-cost.sh tests/test_cost_hook.sh
git commit -m "feat: installer rate-precision guard + UUID session_id path confinement"
```

---

## Task 17: Full acceptance run for the amendment

**Files:** none created — verification only.

- [ ] **Step 1: Run the cost-hook suite**

Run: `bash tests/test_cost_hook.sh`
Expected: `failed=0`, exit 0 — including the new Task 14 (transient skip + self-heal + 0-byte + mid-file-corruption-still-sticky) and Task 16 (non-UUID rejected) cases.

- [ ] **Step 2: Run the policy suite (regression)**

Run: `bash tests/test_policy_hooks.sh`
Expected: `failed=0`, exit 0 — untouched.

- [ ] **Step 3: Run the installer end-to-end**

Run: `bash install.sh && bash install.sh --check`
Expected: `install: OK — ...` then `check: OK — ...`.

- [ ] **Step 4: Confirm no file exceeds 300 lines and no deletion/move was authored in the hook**

Run:
```bash
wc -l hooks/agent-team-cost.sh tests/test_cost_hook.sh
grep -nE '(^|[^-])\b(rm|mv)\b' hooks/agent-team-cost.sh || echo "cost hook: no rm/mv (expected)"
```
Expected: both files under 300 lines; the cost hook contains no `rm`/`mv`. (The test file creates scratch fixtures with `printf`/`cp`/`mkdir` only — no deletion of committed files.)

- [ ] **Step 5: Final commit if anything changed during acceptance**

```bash
git status
git add -A && git commit -m "chore: acceptance run for cost-accounting self-heal amendment" || true
```

---

## Self-Review

**1. Spec coverage.**
- Component 1 (hook: incremental summing, dedup, per-session cost file keyed by session_id under `~/.claude/logs/`, sticky unavailable, exit 0) → Tasks 3–8.
- Component 2 (rates config, never in script) → Task 1; enforced by installer shape-check (Task 9) and by the hook's rule 5e (Task 6 unknown-model).
- Component 3 (cost-file schema) → Task 4 Interfaces + implementation.
- Component 4 (orchestrator two-path closeout + frontmatter hook) → Task 10.
- Component 5 (fixture-driven tests, good/malformed/unknown, all 7 required cases) → Tasks 2–8; case 7 (policy regression) → Task 13 Step 2.
- Component 6 (installer validate + install) → Task 9.
- Files-to-change table: cost hook (T3–8), rates (T1), test + fixtures (T2–8), orchestrator (T10), install.sh (T9), README (T11), parent spec amendment + this spec status (T12). All covered.
- Acceptance Criteria 1–5 → Task 13 Steps 1–4 map one-to-one; float-exactness guard noted in Task 4 Step 1.
- Spec §D7 write-lag self-heal → Task 5 size-changed re-parse. §D3 dedup → Task 4 (c) + good fixture A2. §D8 intro pricing → Task 4 date branch + good fixture B1/B2.

**2. Placeholder scan.** No "TBD"/"handle edge cases"/"similar to Task N". Every code step shows full content. The one deliberate deferral — Task 12 Step 2 says "anchor on the actual on-disk text" — is a Grep-then-Edit instruction, not a missing value, because the parent spec's exact surrounding wording must be matched live; the amendment text to insert is given in full.

**3. Type consistency.** Cost-file key names are identical everywhere: `input_tokens`, `output_tokens`, `cache_write_5m_tokens`, `cache_write_1h_tokens`, `cache_read_tokens`, `cost_usd`, `file_size`, `requests`, `agent_type`, `web_search_requests`, `web_fetch_requests`, `status`, `unavailable_reason`, `dispatches`, `totals`. `parse_dispatch`, `write_unavailable`, `run_hook`, `payload`, `costfile_for` are used consistently. Env vars `AGENT_TEAM_COST_DIR` / `AGENT_TEAM_RATES` match spec Component 1. Slug rule (`/`→`-`) is identical in hook, tests, orchestrator, and README.

Resolved during planning: the malformed-line detection uses `jq -e . "$file"` (whole-file parse fails on any non-JSON line) rather than a per-line loop, which is simpler and matches recognition rule 5a. The good-fixture token values were chosen so every per-model and grand cost is exact at four decimals (0.061, 0.0555, 0.1165), so `jq`'s float printing yields clean equality without a rounding-tolerance helper in the tests.

---

### Self-Review addendum — Amendment 2026-07-09 (Tasks 14–17)

**Spec coverage of the amendment.**
- §D7 / Component 1 step 5 two-mode behavior (transient-skip vs sticky-unavailable) → Task 14: the `is_transient_partial` helper (0-byte OR unterminated final line with valid head) skips the file this fire; every other parse failure still routes to `write_unavailable`. Task 14 Step 6 pins the "genuine mid-file corruption stays sticky" boundary so the fix does not silently loosen the never-a-wrong-number guarantee.
- Self-heal now demonstrably true → Task 14 Step 2's later-fire assertion (`9999pppp` absent this fire, folded in at 0.001125 once complete).
- Nit 1 (stdout comment) → Task 15, comment-only.
- Nit 2 (rate-precision guard) → Task 16 Steps 5–6, extending the installer's existing `jq -e` rate-shape check to bound fractional digits (r*10000 must be integer), intro rates included.
- Nit 3 (UUID session_id path confinement) → Task 16 Steps 1–4, a `case`-glob guard before the cost-file path is built, with a `../../etc/evil` negative test.

**Constraint check.** No new packages (bash + jq only). No `rm`/`mv` authored in hook or tests — Task 14/16 fixtures use `printf`/`cp`/`mkdir`/`:` truncation into scratch dirs only; committed fixtures are created via Write, never deleted. `is_transient_partial` uses `head`/`tail`/`wc` (coreutils, already relied on). The UUID guard uses a `case` glob, not a `[[ =~ ]]` bashism. Files stay under 300 lines (Task 14 Step 7, Task 17 Step 4). No numbers added to the script; the precision bound lives in `install.sh`, and rate values stay only in `model-rates.json`.

**Boundary the fix must NOT cross (data-integrity guarantee kept).** The amendment narrows the sticky-unavailable trigger, so it must not let a genuinely corrupt file slip through as "ok". The discriminator is deliberately conservative: a parse failure is treated as transient ONLY when it is confined to a single unterminated trailing remainder with an otherwise-clean head — the exact and only signature a mid-flush write can produce. Anything else (bad line with good lines after it, shape/dedup/split/model-rate violations) remains sticky-unavailable. Task 14 Step 6 is the regression guard for this line.
