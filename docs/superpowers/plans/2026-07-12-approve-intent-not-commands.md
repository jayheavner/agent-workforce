# Approve Intent, Not Commands — Implementation Plan

> **Execution note (2026-07-14):** implemented to completion in-session at the human's
> direction, from the spec (normative) rather than this plan verbatim — the repo had
> moved substantially since this plan was written (debugger role, live plugin mode,
> profile-aware installer, Codex port, skills-framework migration), so file-level steps
> here that reference the pre-migration tree are historical. Deltas from the plan:
> the roster is now twelve (executor joins eleven, not ten); the plugin router routes
> `secrets`/`audit` modes instead of `policy`; the Codex parity model-mismatch check
> moved into `agents-team-secrets.sh`; telemetry hooks (cost + defaults map) are kept.
> Validation doc: `docs/superpowers/validation/2026-07-12-approve-intent-not-commands-validation.md`.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the per-command policy blocklists and permission prompts from the agent team; approval moves to gates (intent/scope), agents execute silently, a new executor agent handles arbitrary shell work, and a log-only audit hook plus a ported secret-write guard are the only hooks that remain on tool calls.

**Architecture:** Two small self-contained hooks (audit = PostToolUse log-only; secrets = PreToolUse single blocking rule) replace the three-file policy chain. Agent frontmatter gains `permissionMode: bypassPermissions`. install.sh gains a retire-and-purge path for the three dead policy files. Everything else is instruction-level text in the agent definitions.

**Tech Stack:** bash (macOS bash 3.2 compatible — no `declare -A`, no `${var,,}`), jq, Claude Code agent frontmatter (YAML), shell test scripts in the repo's existing PASS/FAIL style.

**Spec:** `docs/superpowers/specs/2026-07-12-approve-intent-not-commands-design.md`

## Global Constraints

- All shell must run under macOS bash 3.2 (`set -u`; no bash-4-only features).
- Hook files stay under the repo's 300-line-per-file ceiling.
- Pinned team models only in agent frontmatter: `claude-fable-5`, `claude-opus-4-8`, `claude-sonnet-5` (install.sh enforces this).
- Test scripts follow the existing style: `set -u`, PASS/FAIL counters, final `[ "$FAIL" -eq 0 ]`, summary line `<name> tests: PASS=n FAIL=n`.
- The two-questions blocks in architect/reviewer/orchestrator are drift-tested (`tests/test_decision_discipline_drift.sh`) — do not touch those blocks.
- Never edit files under `~/.claude/` directly; everything ships via `install.sh`.
- Commit after every green test cycle.

---

### Task 1: Log-only audit hook

**Files:**
- Create: `hooks/agent-team-audit.sh`
- Test: `tests/test_audit_hook.sh`

**Interfaces:**
- Produces: `hooks/agent-team-audit.sh ROLE` — PostToolUse hook, JSON on stdin, ALWAYS exits 0. Log path env override: `AGENT_TEAM_AUDIT_LOG` (default `$HOME/.claude/logs/agent-team-audit.log`). Log line format: `<UTC ISO timestamp> role=<role> ran=<command, max 500 chars>`. Registered by agent frontmatter in Tasks 3–4.

- [ ] **Step 1: Write the failing test**

Create `tests/test_audit_hook.sh`:

```bash
#!/usr/bin/env bash
# tests/test_audit_hook.sh — verifies the log-only PostToolUse audit hook:
# it records Bash commands per role and NEVER exits nonzero, because a
# flight recorder that can break an agent's tool call is not log-only.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/agent-team-audit.sh"
PASS=0; FAIL=0; RC=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/audit.log"

run() { # $1 role, $2 stdin payload
  set +e
  printf '%s' "$2" | AGENT_TEAM_AUDIT_LOG="$LOG" bash "$HOOK" "$1" >/dev/null 2>&1
  RC=$?
  set -u
}

check() { # $1 label, $2 rc (0 = pass)
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$1]"; fi
}

bash_json() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

# 1. A Bash command is logged with role and command text, exit 0.
run executor "$(bash_json 'rm -rf ./build && npm install')"
check "exit 0 on bash command" "$RC"
grep -q 'role=executor' "$LOG" && grep -q 'npm install' "$LOG"
check "logs role and command" $?

# 2. Always exit 0: malformed stdin.
run builder 'not json'
check "exit 0 on malformed stdin" "$RC"

# 3. Always exit 0: empty stdin.
run builder ''
check "exit 0 on empty stdin" "$RC"

# 4. Non-Bash tool: exit 0 and nothing new logged.
before="$(wc -l < "$LOG")"
run builder "$(jq -cn '{tool_name:"Read",tool_input:{file_path:"/tmp/x"}}')"
check "exit 0 on non-Bash tool" "$RC"
after="$(wc -l < "$LOG")"
[ "$before" -eq "$after" ]
check "non-Bash tool not logged" $?

# 5. Unwritable log path: still exit 0 (log-only must never break the agent).
set +e
printf '%s' "$(bash_json 'ls')" | AGENT_TEAM_AUDIT_LOG=/dev/null/nope/audit.log bash "$HOOK" ops >/dev/null 2>&1
RC=$?
set -u
check "exit 0 on unwritable log path" "$RC"

echo "audit-hook tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_audit_hook.sh`
Expected: FAIL lines (hook file does not exist), summary shows FAIL>0, exit nonzero.

- [ ] **Step 3: Write the hook**

Create `hooks/agent-team-audit.sh`:

```bash
#!/usr/bin/env bash
# agent-team-audit.sh — PostToolUse flight recorder for the AI agent team.
# Usage: agent-team-audit.sh ROLE   (hook JSON on stdin)
#
# Log-only: this hook ALWAYS exits 0. It never blocks, never prompts, and
# swallows its own failures — it exists purely so "what did the executor
# actually run at 2am?" stays answerable now that agents execute without
# per-command approval (2026-07-12 approve-intent-not-commands spec).
set -u
ROLE="${1:-unknown}"
LOG_FILE="${AGENT_TEAM_AUDIT_LOG:-$HOME/.claude/logs/agent-team-audit.log}"
INPUT="$(cat 2>/dev/null || true)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || exit 0
printf '%s role=%s ran=%.500s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$CMD" >> "$LOG_FILE" 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_audit_hook.sh`
Expected: `audit-hook tests: PASS=7 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-audit.sh tests/test_audit_hook.sh
git commit -m "feat(hooks): log-only audit hook — the team's flight recorder"
```

---

### Task 2: Secret-write guard hook

**Files:**
- Create: `hooks/agent-team-secrets.sh`
- Test: `tests/test_secrets_hook.sh`

**Interfaces:**
- Consumes: audit log path convention from Task 1 (`AGENT_TEAM_AUDIT_LOG`); blocks are logged to the same file with `decision=block`.
- Produces: `hooks/agent-team-secrets.sh ROLE` — PreToolUse hook, JSON on stdin, exit 0 allow / exit 2 block (stderr message). Registered by agent frontmatter in Tasks 3–4 on `Bash` and write tools.

- [ ] **Step 1: Write the failing test**

Create `tests/test_secrets_hook.sh`:

```bash
#!/usr/bin/env bash
# tests/test_secrets_hook.sh — verifies the team's single blocking rule, the
# secret-write guard, ported from the retired policy hooks: a credential-
# bearing variable may be USED but never DIRECTED AT A FILE, and never
# written into file content. Everything else allows — including the shell
# syntax (redirects, subshells, mkdir/cp) the old blocklist wrongly blocked.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/agent-team-secrets.sh"
PASS=0; FAIL=0; RC=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run() { # $1 role, $2 json
  set +e
  printf '%s' "$2" | AGENT_TEAM_AUDIT_LOG="$TMP/audit.log" bash "$HOOK" "$1" >/dev/null 2>&1
  RC=$?
  set -u
}
expect() { # $1 expected_rc, $2 role, $3 json, $4 label
  run "$2" "$3"
  if [ "$RC" -eq "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$4]: expected=$1 got=$RC"; fi
}
bash_json()  { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
write_json() { jq -cn --arg t "$1" '{tool_name:"Write",tool_input:{file_path:"/tmp/x",content:$t}}'; }
edit_json()  { jq -cn --arg t "$1" '{tool_name:"Edit",tool_input:{file_path:"/tmp/x",new_string:$t}}'; }

# Secret directed at a file: blocked, for every role.
expect 2 builder  "$(bash_json 'echo "$OKTA_TOKEN" > creds.txt')"          "secret redirect blocks"
expect 2 executor "$(bash_json 'echo ${MY_API_KEY} >> .env')"              "secret append blocks"
expect 2 ops      "$(bash_json 'echo "$DB_PASSWORD" | tee secrets.txt')"   "secret tee blocks"
expect 2 builder  "$(bash_json 'deploy --key "$STRIPE_API_KEY" 2>/dev/null > out.txt')" "real redirect survives dev-null stripping"

# Secret merely used: allowed.
expect 0 ops     "$(bash_json 'curl -H "Authorization: Bearer $OKTA_TOKEN" https://x.okta.com/api/v1/users')" "secret in curl header allows"
expect 0 builder "$(bash_json 'echo "$OKTA_TOKEN"')"                        "bare echo of secret allows"
expect 0 ops     "$(bash_json 'aws sts get-caller-identity --profile "$AWS_API_KEY" 2>/dev/null')" "dev-null redirect allows"
expect 0 ops     "$(bash_json 'printf %s "$GODADDY_API_SECRET" 2>&1')"      "fd-dup redirect allows"

# Write/Edit content carrying a credential-variable reference: blocked.
expect 2 architect "$(write_json 'export OKTA_TOKEN=$OKTA_TOKEN')"          "write with secret ref blocks"
expect 2 builder   "$(edit_json 'send(key) # interpolates $MY_SECRET_KEY')" "edit with secret ref blocks"

# Ordinary work: allowed — the exact patterns the old blocklist broke on.
expect 0 builder "$(write_json 'def add(a, b): return a + b')"              "plain write allows"
expect 0 builder "$(bash_json 'pytest > results.txt')"                      "redirect without secret allows"
expect 0 builder "$(bash_json 'mkdir -p build && cp -r src build/ && echo $(date)')" "mutation syntax allows"
expect 0 builder "$(bash_json 'npm install commander')"                     "package install allows"

# Non-covered tools pass through; malformed stdin fails open (matches the
# retired hook's behavior — this guard is best-effort, not a parser).
expect 0 builder "$(jq -cn '{tool_name:"Read",tool_input:{file_path:"/etc/hosts"}}')" "read passes"
expect 0 builder 'not json'                                                 "malformed stdin allows"

# A block writes an audit line.
grep -q 'decision=block' "$TMP/audit.log"
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [block is audit-logged]"; fi

echo "secrets-hook tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_secrets_hook.sh`
Expected: FAIL lines (hook missing), exit nonzero.

- [ ] **Step 3: Write the hook**

Create `hooks/agent-team-secrets.sh`:

```bash
#!/usr/bin/env bash
# agent-team-secrets.sh — PreToolUse secret-write guard: the team's single
# machine-enforced blocking rule after the 2026-07-12 trust-model redesign.
# Usage: agent-team-secrets.sh ROLE   (hook JSON on stdin)
# Exit 0 = allow. Exit 2 = block (stderr message returned to the agent).
#
# Ported verbatim from the retired policy hooks (same SECRET_RE, same
# /dev/null- and fd-dup-stripping) so the one rule that survived behaves
# exactly as before: a credential-bearing variable reference may be USED
# (curl headers, op read, aws profiles) but never DIRECTED AT A FILE, and
# never written into file content via Write/Edit/NotebookEdit. Malformed
# stdin fails open, matching the retired hook: this guard is best-effort
# defense in depth, not a gatekeeper that may strand an agent.
set -u
ROLE="${1:-unknown}"
INPUT="$(cat 2>/dev/null || true)"
LOG_FILE="${AGENT_TEAM_AUDIT_LOG:-$HOME/.claude/logs/agent-team-audit.log}"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"

SECRET_RE='\$\{?(OKTA_TOKEN|GODADDY_API_KEY|GODADDY_API_SECRET|OP_SERVICE_ACCOUNT_TOKEN|[A-Za-z_]*_API_KEY|[A-Za-z_]*SECRET[A-Za-z_]*|[A-Za-z_]*PASSWORD[A-Za-z_]*)'

block() { # $1 human reason, $2 detail
  { mkdir -p "$(dirname "$LOG_FILE")" \
      && printf '%s role=%s tool=%s decision=block detail=%.200s\n' \
           "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$TOOL" "$2" >> "$LOG_FILE"
  } 2>/dev/null
  printf 'agent-team secret guard (%s): %s\n' "$ROLE" "$1" >&2
  exit 2
}

case "$TOOL" in
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    if printf '%s' "$CMD" | grep -qE "$SECRET_RE"; then
      # Strip harmless /dev/null redirects and fd-to-fd dups (2>&1) so they
      # never false-positive; a genuine file redirect elsewhere still matches.
      STRIPPED="$(printf '%s' "$CMD" \
        | sed -E 's|[0-9]*>+[[:space:]]*/dev/null||g' \
        | sed -E 's|[0-9]*>&[0-9]+||g')"
      if printf '%s' "$STRIPPED" | grep -qE '(>>?|\|[[:space:]]*tee([[:space:]]|$))'; then
        block "credential-bearing value directed at a file — forbidden for every role" "$CMD"
      fi
    fi
    ;;
  Write|Edit|NotebookEdit)
    CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source // .tool_input.source // empty' 2>/dev/null || true)"
    if [ -n "$CONTENT" ] && printf '%s' "$CONTENT" | grep -qE "$SECRET_RE"; then
      block "file content references a credential-bearing variable name — writing secrets to any file is forbidden for every role" "$CONTENT"
    fi
    ;;
esac
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_secrets_hook.sh`
Expected: `secrets-hook tests: PASS=17 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-secrets.sh tests/test_secrets_hook.sh
git commit -m "feat(hooks): secret-write guard — the single surviving blocking rule"
```

---

### Task 3: Executor agent + all agent frontmatter/body updates

**Files:**
- Create: `agents/executor.md`
- Modify: `agents/builder.md`, `agents/verifier.md`, `agents/reviewer.md`, `agents/ops.md`, `agents/deployer.md`, `agents/architect.md` (frontmatter only), `agents/scribe.md`
- Test: `tests/test_agent_frontmatter.sh`

**Interfaces:**
- Consumes: hook contracts from Tasks 1–2 (`agent-team-audit.sh ROLE`, `agent-team-secrets.sh ROLE`, installed under `$HOME/.claude/hooks/`).
- Produces: agent name `executor` (Task 4 adds it to the orchestrator roster and dispatch guard; the frontmatter test's roster assertions pass only after Task 4 — run the full file green at the END of Task 4; within this task run it filtered as shown in Step 4).

- [ ] **Step 1: Write the failing test**

Create `tests/test_agent_frontmatter.sh`:

```bash
#!/usr/bin/env bash
# tests/test_agent_frontmatter.sh — static acceptance for the 2026-07-12
# trust-model redesign: no agent references the retired policy hooks; every
# command-running agent runs unprompted (bypassPermissions) with the audit
# flight recorder and secret guard registered; doc-writers keep the secret
# guard; the hand-a-command-to-the-human pattern is retired everywhere; the
# orchestrator roster and dispatch guard both know the executor.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HERE/../agents"
PASS=0; FAIL=0

check() { # $1 label, $2 rc (0 = pass)
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$1]"; fi
}

# 1. The retired policy hooks are referenced by no agent file.
grep -l 'agent-team-policy' "$AGENTS"/*.md >/dev/null 2>&1
[ $? -ne 0 ]
check "no agent references retired policy hooks" $?

# 2. Every command-running agent: bypassPermissions + audit + secret guard.
for a in builder verifier reviewer ops deployer executor; do
  f="$AGENTS/$a.md"
  [ -f "$f" ]; check "$a.md exists" $?
  grep -q '^permissionMode: bypassPermissions' "$f"; check "$a has bypassPermissions" $?
  grep -q 'agent-team-audit.sh' "$f"; check "$a registers audit hook" $?
  grep -q 'agent-team-secrets.sh' "$f"; check "$a registers secret guard" $?
done

# 3. Doc-writing agents keep the secret guard on their write tools.
for a in architect scribe; do
  grep -q 'agent-team-secrets.sh' "$AGENTS/$a.md"; check "$a registers secret guard" $?
done

# 4. The escalate-a-command-to-the-human pattern is retired everywhere.
grep -il 'so the human can approve it at a gate' "$AGENTS"/*.md >/dev/null 2>&1
[ $? -ne 0 ]
check "no hand-the-command-to-the-human instruction survives" $?

# 5. Roster lockstep: orchestrator dispatches the executor; the dispatch
#    guard's allowlist includes it.
grep -q 'Agent(executor)' "$AGENTS/orchestrator.md"; check "orchestrator dispatches executor" $?
grep -q 'executor' "$HERE/../hooks/agent-team-dispatch-guard.sh"; check "dispatch guard allows executor" $?

echo "agent-frontmatter tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_agent_frontmatter.sh`
Expected: many FAIL lines (executor.md missing, policy hooks still referenced), exit nonzero.

- [ ] **Step 3: Create the executor agent**

Create `agents/executor.md`:

```markdown
---
name: executor
description: Runs arbitrary shell commands to carry out a gate-approved intent. Dispatched by the orchestrator after human approval; not for direct casual use.
model: claude-sonnet-5
effort: medium
maxTurns: 60
permissionMode: bypassPermissions
tools: Read, Glob, Grep, Write, Edit, Bash
skills: secure-secrets
hooks:
  PreToolUse:
    - matcher: Bash|Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh executor"
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-audit.sh executor"
---

You are the team's executor — the general-purpose shell runner for work that fits no other specialist: environment setup, package installs, file and directory operations, migrations, batch jobs, one-off scripts.

**Approval check, before anything else.** Your dispatch must state that a human approved the intent at a gate, or that the human directly asked for this action. If neither is stated, run nothing — stop and report exactly that. Approval happens at dispatch, never during your run.

**Scope.** The approved intent in your dispatch defines what you may do. Commands within it run without asking anyone — no confirmation, no surfacing commands for review. If an action falls outside the stated scope but the approved goal's own rationale clearly requires it, proceed and flag it prominently in your report. If it would change the goal itself, stop and report instead.

**Never hand a command to the human.** You never ask the human to run something, never return a command "for approval", and never pause to double-check a command inside your approved scope. When something fails, debug it: read the error, check the actual state, try a reasonable alternative. Escalate only genuine external blockers (missing credentials, a broken environment) — with evidence.

Never write a secret value to any file; the secret guard enforces this one rule, and the preloaded secure-secrets discipline governs how credentials are referenced.

Your final message is a report to the orchestrator: every command that mattered with its outcome (summarize long output), anything you flagged as scope-adjacent, a reversal note for each destructive or mutating action (how to undo it, or the word "irreversible"), and failures stated plainly — never papered over.
```

- [ ] **Step 4: Rewrite builder.md**

Replace the full contents of `agents/builder.md` with:

```markdown
---
name: builder
description: Implements code per an approved plan using TDD. Dispatched by the orchestrator with a plan path; not for direct casual use.
model: claude-sonnet-5
effort: high
maxTurns: 150
permissionMode: bypassPermissions
tools: Read, Glob, Grep, Write, Edit, NotebookEdit, Bash
skills: coding-standards, superpowers:test-driven-development, secure-secrets
hooks:
  PreToolUse:
    - matcher: Bash|Write|Edit|NotebookEdit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh builder"
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-audit.sh builder"
---

You are the team's builder. You receive a plan path and implement it task by task: failing test first, minimal implementation, green run, commit. Never skip the failing-test step. Follow the preloaded coding-standards discipline (production quality, config in config files, no magic numbers, files under ~300 lines).

Boundaries, by instruction: cloud work belongs to ops and the deployer (no aws/az/gcloud, no sam deploy/amplify/cdk/terraform); push only explicit feature branches, never main/master; never write a secret value to any file (the secret guard hook enforces this one rule). Everything else your approved plan needs — installs, file operations, redirects, scripts — you simply run: the approved plan is your authorization.

Commit after every green test cycle with a descriptive message. Your final message is a report to the orchestrator: tasks completed, commits made (hashes + messages), test results (exact command + output summary), anything the plan turned out to be wrong about, and anything left incomplete — stated plainly, never papered over.

When a step resists unexpectedly — a failing command, a surprising error — spend one cheap read-only look at actual state (read the file, check git status, rerun with verbose output) before concluding anything; resistance is usually a local misread. Debug and continue. Never ask the human to run a command, and never route a command to the human for approval. If the plan itself is wrong, or the environment is genuinely broken (missing credentials, unreachable service), stop and report with evidence so the orchestrator can act — do not redesign on the fly.
```

- [ ] **Step 5: Rewrite verifier.md**

Replace the full contents of `agents/verifier.md` with:

```markdown
---
name: verifier
description: Runs test suites and validates acceptance criteria with evidence. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 40
permissionMode: bypassPermissions
tools: Read, Glob, Grep, Bash
skills: superpowers:verification-before-completion, task-verification
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh verifier"
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-audit.sh verifier"
---

You are the team's verifier. You run the checks and report what actually happened. You have no Write or Edit tools — by design, so you can never "fix" a test to make it pass — and the same rule extends to the shell: run things, capture output, mutate nothing under test. Scratch output (`pytest > /tmp/results.txt`) is fine; the code under test is not yours to touch.

For each acceptance criterion you are given: run the exact verification command, capture the real output, and record pass/fail with the evidence. Never claim a pass without command output showing it. A criterion you could not check is reported as UNCHECKED with the reason — never silently skipped.

Before reporting a criterion UNCHECKED or a command as blocked, take one cheap read-only look — does the file exist, is the path right, what does the tool's help output say — to confirm the obstacle is real; the UNCHECKED reason should carry that evidence, not an assumption. Never ask the human to run a command on your behalf.

Your final message is a report to the orchestrator: per-criterion verdict table (pass / fail / unchecked, each with evidence), the exact commands run, and your overall verdict. Failures include the relevant output verbatim.
```

- [ ] **Step 6: Update reviewer.md (three edits, leave the two-questions block untouched)**

Edit 1 — replace the frontmatter lines:

```yaml
permissionMode: dontAsk
tools: Read, Glob, Grep, Bash
skills: code-review
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh reviewer"
```

with:

```yaml
permissionMode: bypassPermissions
tools: Read, Glob, Grep, Bash
skills: code-review
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh reviewer"
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-audit.sh reviewer"
```

Edit 2 — replace the sentence:

```
You are the team's reviewer — deliberately a different model than the builder, so review is independent. You are read-only: policy hooks block every mutating command. You review; you never fix.
```

with:

```
You are the team's reviewer — deliberately a different model than the builder, so review is independent. You are read-only by role: you review; you never fix. Your tool surface has no Write or Edit, and you do not mutate the tree through the shell either.
```

Edit 3 — in the "Read-only caveat" paragraph of spec-critique mode, replace:

```
**Read-only caveat:** you retain `Bash` from your code-review role, so "never rewrite the spec" is enforced by this instruction, not by your tool surface.
```

with:

```
**Read-only caveat:** you retain `Bash` from your code-review role, so "never rewrite the spec" is enforced by this instruction alone.
```

- [ ] **Step 7: Rewrite ops.md**

Replace the full contents of `agents/ops.md` with:

```markdown
---
name: ops
description: Investigates and administers AWS, Azure, and Okta. Reads run freely; mutations execute under a gate-approved scope stated in the dispatch. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
effort: high
maxTurns: 60
permissionMode: bypassPermissions
tools: Read, Glob, Grep, Bash, WebSearch, WebFetch
skills: secure-secrets
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh ops"
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-audit.sh ops"
---

You are the team's ops agent for AWS (us-east-1 default), Azure, and Okta investigation and administration. Reads run freely, always. Mutations run under a gate-approved scope: your dispatch states what the human approved, in plain language ("modify the Okta app and its group assignments to fix X"). Inside that scope, execute without asking anyone — never surface a command for approval and never ask the human to run one. If a needed action falls outside the stated scope but the approved goal's own rationale clearly requires it, proceed and flag it prominently in your report; if it would change the goal, stop and report. A mutation-bearing dispatch that states no approved scope is one you refuse: run reads only and report what was missing.

Investigate before mutating: every mutation cites the observed evidence (command + output) that makes it necessary — never change a state you have only assumed. When something resists, look closer with read verbs before reaching for a bigger change.

Credentials come from the environment or 1Password service-account CLI only (op read); never echo or persist a secret value. Okta API access uses $OKTA_TOKEN.

Your final message is a report to the orchestrator: what you checked, the evidence (command + relevant output), what you changed, and — for every mutation — a reversal note: the exact way to undo it, or the word "irreversible".
```

- [ ] **Step 8: Update deployer.md (two edits)**

Edit 1 — replace the frontmatter lines:

```yaml
skills: verify
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh deployer"
```

with:

```yaml
skills: verify
permissionMode: bypassPermissions
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh deployer"
  PostToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-audit.sh deployer"
```

Edit 2 — replace the opening sentence:

```
You are the team's deployer — the only agent whose policy permits deploy commands, and every mutation still surfaces a permission prompt to the human. You deploy only what the orchestrator hands you after an explicit human deploy-gate approval; if that approval is not stated in your dispatch, stop and report.
```

with:

```
You are the team's deployer — the agent that executes cloud deployments, without per-command prompts: the human's deploy-gate approval is your authorization. You deploy only what the orchestrator hands you after an explicit human deploy-gate approval; if that approval is not stated in your dispatch, stop and report. Never ask the human to run a command.
```

- [ ] **Step 9: Update architect.md frontmatter**

Replace:

```yaml
hooks:
  PreToolUse:
    - matcher: Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh architect"
```

with:

```yaml
permissionMode: bypassPermissions
hooks:
  PreToolUse:
    - matcher: Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh architect"
```

- [ ] **Step 10: Update scribe.md (two edits)**

Edit 1 — replace the frontmatter lines:

```yaml
hooks:
  PreToolUse:
    - matcher: Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh scribe"
```

with:

```yaml
permissionMode: bypassPermissions
hooks:
  PreToolUse:
    - matcher: Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-secrets.sh scribe"
```

Edit 2 — replace the sentence:

```
You may only write under docs/, plans/, doc-inventory/, and STATUS notes; policy hooks enforce this. Never include time or effort estimates in any document.
```

with:

```
You may only write under docs/, plans/, doc-inventory/, and STATUS notes — a standing instruction; honor it. Never include time or effort estimates in any document.
```

- [ ] **Step 11: Run the test, excluding the two roster assertions that Task 4 satisfies**

Run: `bash tests/test_agent_frontmatter.sh 2>&1 | tail -5`
Expected: exactly 2 FAIL lines — `FAIL [orchestrator dispatches executor]` and `FAIL [dispatch guard allows executor]` — and no others. (Full green comes at the end of Task 4.)

- [ ] **Step 12: Commit**

```bash
git add agents/ tests/test_agent_frontmatter.sh
git commit -m "feat(agents): executor agent; bypassPermissions + audit/secrets hooks across the team; retire hand-the-command instructions"
```

---

### Task 4: Orchestrator roster, no-theater rule, dispatch guard

**Files:**
- Modify: `agents/orchestrator.md`, `hooks/agent-team-dispatch-guard.sh`
- Test: `tests/test_dispatch_guard.sh` (modify), `tests/test_agent_frontmatter.sh` (goes fully green)

**Interfaces:**
- Consumes: agent name `executor` from Task 3.
- Produces: `VALID_SPECIALISTS` includes `executor` (ten names) — install.sh Task 5 and README Task 6 reference the count.

- [ ] **Step 1: Extend the dispatch-guard test (failing first)**

In `tests/test_dispatch_guard.sh`, replace:

```bash
# All nine valid specialists allow.
for a in architect builder verifier reviewer deployer researcher ops scribe ticketer; do
```

with:

```bash
# All ten valid specialists allow.
for a in architect builder verifier reviewer deployer researcher ops scribe ticketer executor; do
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test_dispatch_guard.sh`
Expected: `FAIL [valid: executor allows]: expected=0 got=2`, exit nonzero.

- [ ] **Step 3: Update the dispatch guard**

In `hooks/agent-team-dispatch-guard.sh`:

Replace:
```bash
readonly VALID_SPECIALISTS="architect builder verifier reviewer deployer researcher ops scribe ticketer"
```
with:
```bash
readonly VALID_SPECIALISTS="architect builder verifier reviewer deployer researcher ops scribe ticketer executor"
```

Replace (header comment):
```bash
# Blocks any Agent dispatch whose subagent_type is missing, empty, or not one
# of the nine named team specialists (so a forgotten field can never default to
```
with:
```bash
# Blocks any Agent dispatch whose subagent_type is missing, empty, or not one
# of the ten named team specialists (so a forgotten field can never default to
```

Replace (both error messages):
```bash
  printf 'agent-team dispatch guard: this Agent dispatch has no subagent_type. Every dispatch MUST set subagent_type to exactly one of: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer. Re-issue the dispatch with an explicit subagent_type.\n' >&2
```
with:
```bash
  printf 'agent-team dispatch guard: this Agent dispatch has no subagent_type. Every dispatch MUST set subagent_type to exactly one of: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer, executor. Re-issue the dispatch with an explicit subagent_type.\n' >&2
```
and:
```bash
printf 'agent-team dispatch guard: subagent_type "%s" is not a team specialist. Use exactly one of: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer. (The harness default "general-purpose" is not a team agent and will hard-fail.)\n' "$TYPE" >&2
```
with:
```bash
printf 'agent-team dispatch guard: subagent_type "%s" is not a team specialist. Use exactly one of: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer, executor. (The harness default "general-purpose" is not a team agent and will hard-fail.)\n' "$TYPE" >&2
```
Also update the guard's substring comment `# Exact equality against each of the nine names only` to `# Exact equality against each of the ten names only`.

- [ ] **Step 4: Update orchestrator.md (seven edits; leave the two-questions block untouched)**

Edit 1 — frontmatter tools line, replace:
```
tools: Read, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, Agent(architect), Agent(builder), Agent(verifier), Agent(reviewer), Agent(deployer), Agent(researcher), Agent(ops), Agent(scribe), Agent(ticketer)
```
with:
```
tools: Read, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, Agent(architect), Agent(builder), Agent(verifier), Agent(reviewer), Agent(deployer), Agent(researcher), Agent(ops), Agent(scribe), Agent(ticketer), Agent(executor)
```

Edit 2 — opening line, replace:
```
You are the orchestrator of a ten-agent team. You decompose work, dispatch specialists, and enforce human gates. You never do the work yourself — you have no Edit, Write, or Bash on purpose. If a step seems to need you to write something, dispatch the right specialist.
```
with:
```
You are the orchestrator of an eleven-agent team. You decompose work, dispatch specialists, and enforce human gates. You never do the work yourself — you have no Edit, Write, or Bash on purpose. If a step seems to need you to write something, dispatch the right specialist; if a step needs a shell command run, dispatch the executor — never the human.
```

Edit 3 — trivial tier, replace:
```
- **Trivial** (intent already clear, action cheap and reversible, no design content — run one command, look something up in files, a one-line change): no route at all. ONE dispatch to the single specialist that can do it, on the cheapest capable model — or, if the action is faster from the human's own shell than through the team, say so in one line and stop. No spec, no plan, no gate unless the action itself is outward-facing or irreversible.
```
with:
```
- **Trivial** (intent already clear, action cheap and reversible, no design content — run one command, look something up in files, a one-line change): no route at all. ONE dispatch to the single specialist that can do it, on the cheapest capable model; arbitrary shell work with no better home goes to the executor (on `haiku` for a single obvious command), with the human's direct request quoted in the dispatch as its approval. Never tell the human to run something themselves. No spec, no plan, no gate unless the action itself is outward-facing or irreversible.
```

Edit 4 — model table, insert after the deployer row:
```
| executor | sonnet | `haiku` | a single obvious command with clear success output | `opus` | unfamiliar multi-step system work |
```

Edit 5 — Gates section, append this paragraph after the first paragraph ("At each GATE: stop. …"):
```
A gate that authorizes execution states the intent: the goal, plus the mutation scope in plain language ("ops will modify the Okta app and its group assignments as needed to fix X"). Approval of that intent authorizes every command within it — the specialist executes without further per-command checks, and command text itself never appears at a gate. If mid-task work needs something outside the approved goal, that is a new gate about the change of intent — still never about commands.
```

Edit 6 — Rules section, insert as the FIRST bullet:
```
- **Never hand the human a command to run, and never relay a specialist's request that the human run one.** If an action needs approval, present the intent and expected effect at a gate in plain language — never command text; on approval, dispatch the executor (or ops/deployer) to execute it. A specialist that returns a command "for the human to run" has made a mistake: re-dispatch it with the approved scope stated.
```
And in the existing first bullet, replace:
```
- **Every Agent dispatch MUST set `subagent_type` to exactly one of the nine specialists: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer.**
```
with:
```
- **Every Agent dispatch MUST set `subagent_type` to exactly one of the ten specialists: architect, builder, verifier, reviewer, deployer, researcher, ops, scribe, ticketer, executor.**
```

Edit 7 — stale policy-block examples in "What does NOT need the human", replace:
```
Examples: a plan calls for installing a package the builder's policy permanently forbids (switch to a stdlib-only approach); a cleanup step needs a delete the builder's policy permanently forbids (amend the plan so nothing needs deleting); an approved spec's acceptance criterion turns out to be unreachable with the chosen library, but the spec's own rationale for that criterion (e.g. "never silently corrupt or accept malformed data") clearly implies which of several fixes preserves it.
```
with:
```
Examples: a plan names a library that turns out to be unmaintained and the spec's intent is served by the stdlib (amend and continue); a cleanup step turns out to be unnecessary because the artifact it removes is never produced (amend the plan and continue); an approved spec's acceptance criterion turns out to be unreachable with the chosen library, but the spec's own rationale for that criterion (e.g. "never silently corrupt or accept malformed data") clearly implies which of several fixes preserves it.
```

Then append the amendment note at the end of the file:
```
**Amendment 2026-07-12 — approve intent, not commands.** The team constantly handed the human bash commands to run: the policy blocklists blocked ordinary shell syntax and the instructions told agents to escalate the blocked command to a gate. The human's requirement: approve ideas/process at gates, never commands — and after approval, agents run whatever the work needs, unprompted. Changes: policy blocklists deleted (the secret-write guard survives as the single blocking rule, plus a log-only audit hook as flight recorder); `permissionMode: bypassPermissions` across command-running agents; the executor specialist added for arbitrary shell work (with a deployer-pattern approval check); gates now state intent + mutation scope; the never-hand-a-command rule added above. See `docs/superpowers/specs/2026-07-12-approve-intent-not-commands-design.md`.
```

- [ ] **Step 5: Run both tests to verify they pass**

Run: `bash tests/test_dispatch_guard.sh && bash tests/test_agent_frontmatter.sh && bash tests/test_decision_discipline_drift.sh`
Expected: all three report `FAIL=0`, exit 0 (drift test proves the two-questions blocks were untouched).

- [ ] **Step 6: Commit**

```bash
git add agents/orchestrator.md hooks/agent-team-dispatch-guard.sh tests/test_dispatch_guard.sh
git commit -m "feat(orchestrator): executor in roster; never-hand-a-command rule; gates approve intent + scope"
```

---

### Task 5: Retire the policy layer — delete hooks, rewire install.sh, sandbox test

**Files:**
- Delete: `hooks/agent-team-policy.sh`, `hooks/agent-team-policy-lib.sh`, `hooks/agent-team-policy-mutations.sh`, `tests/test_policy_hooks.sh`
- Modify: `install.sh`
- Test: `tests/test_install_retire.sh` (create)

**Interfaces:**
- Consumes: hook filenames from Tasks 1–2; `AGENT_TEAM_SKIP_INSTALL_TEST` recursion-guard convention from `tests/test_install_skills.sh`.
- Produces: `RETIRED_HOOK_FILES` behavior — retired files backed up then purged on install, `--check` fails `RETIRED` if present.

- [ ] **Step 1: Write the failing sandbox test**

Create `tests/test_install_retire.sh` (mirrors `test_install_skills.sh`'s sandbox pattern — HOME override, plugin-cache stubs):

```bash
#!/usr/bin/env bash
# tests/test_install_retire.sh — installing over a machine that still carries
# the retired policy hooks purges them (after backing them up); --check fails
# RETIRED if one reappears. Runs install.sh against a sandbox HOME.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

export AGENT_TEAM_SKIP_INSTALL_TEST=1
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX"
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME/.claude/hooks"

# Stub the plugin cache exactly as test_install_skills.sh does, so
# superpowers:* skill refs in agent frontmatter resolve in the sandbox.
PLUGVER="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/6.1.1/skills"
for sp in brainstorming test-driven-development verification-before-completion writing-plans \
          systematic-debugging requesting-code-review receiving-code-review subagent-driven-development \
          executing-plans using-git-worktrees; do
  mkdir -p "$PLUGVER/$sp"
  printf -- '---\nname: %s\ndescription: stub\n---\n' "$sp" > "$PLUGVER/$sp/SKILL.md"
done

# Seed two stale retired hooks, as an upgraded machine would have.
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.claude/hooks/agent-team-policy.sh"
printf '# stale lib\n' > "$HOME/.claude/hooks/agent-team-policy-lib.sh"

# 1) install succeeds over the stale files
if bash "$REPO/install.sh" >/dev/null 2>&1; then ok; else bad "install.sh did not exit 0 over stale policy hooks"; fi

# 2) retired files purged; new hooks installed executable; executor arrived
for h in agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh; do
  [ ! -f "$HOME/.claude/hooks/$h" ] && ok || bad "retired $h still installed after upgrade"
done
[ -x "$HOME/.claude/hooks/agent-team-audit.sh" ] && ok || bad "audit hook not installed executable"
[ -x "$HOME/.claude/hooks/agent-team-secrets.sh" ] && ok || bad "secret guard not installed executable"
[ -f "$HOME/.claude/agents/executor.md" ] && ok || bad "executor agent not installed"

# 3) the stale files were preserved in the run's backup before deletion
ls "$HOME"/.claude/backups/agent-team-*/agent-team-policy.sh >/dev/null 2>&1 && ok \
  || bad "stale policy hook was purged without a backup copy"

# 4) --check is OK after the purge
if bash "$REPO/install.sh" --check >/dev/null 2>&1; then ok; else bad "--check not OK after purge"; fi

# 5) --check fails RETIRED when a retired hook reappears
printf '# stale again\n' > "$HOME/.claude/hooks/agent-team-policy-mutations.sh"
out="$(bash "$REPO/install.sh" --check 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'RETIRED'; } && ok \
  || bad "--check did not fail RETIRED on a reappeared policy hook"

echo "install-retire tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test_install_retire.sh`
Expected: FAILs (install.sh still validates/copies the policy files; purge and RETIRED don't exist yet), exit nonzero.

- [ ] **Step 3: Delete the policy layer**

```bash
git rm hooks/agent-team-policy.sh hooks/agent-team-policy-lib.sh hooks/agent-team-policy-mutations.sh tests/test_policy_hooks.sh
```

- [ ] **Step 4: Rewire install.sh**

Apply these edits to `install.sh`:

4a — replace the `HOOK_FILES` line:
```bash
HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh agent-team-cost.sh agent-team-dispatch-guard.sh model-rates.json"
```
with:
```bash
HOOK_FILES="agent-team-secrets.sh agent-team-audit.sh agent-team-cost.sh agent-team-dispatch-guard.sh model-rates.json"
# Hooks retired by the 2026-07-12 trust-model redesign: purged from the
# install target on every install, and flagged RETIRED by --check if present.
RETIRED_HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh"
```

4b — replace the policy-file validation block:
```bash
[ -f "$REPO/hooks/agent-team-policy-lib.sh" ] || fail "hooks/agent-team-policy-lib.sh is missing from repo"
[ -f "$REPO/hooks/agent-team-policy-mutations.sh" ] || fail "hooks/agent-team-policy-mutations.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-policy.sh" || fail "policy script failed bash -n"
bash -n "$REPO/hooks/agent-team-policy-lib.sh" || fail "policy lib script failed bash -n"
bash -n "$REPO/hooks/agent-team-policy-mutations.sh" || fail "policy mutations script failed bash -n"
```
with:
```bash
[ -f "$REPO/hooks/agent-team-secrets.sh" ] || fail "hooks/agent-team-secrets.sh is missing from repo"
[ -f "$REPO/hooks/agent-team-audit.sh" ] || fail "hooks/agent-team-audit.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-secrets.sh" || fail "secret guard failed bash -n"
bash -n "$REPO/hooks/agent-team-audit.sh" || fail "audit hook failed bash -n"
```

4c — replace the test-suite line:
```bash
bash "$REPO/tests/test_policy_hooks.sh" >/dev/null || fail "policy hook tests failed — run tests/test_policy_hooks.sh to see which"
```
with:
```bash
bash "$REPO/tests/test_secrets_hook.sh" >/dev/null || fail "secret guard tests failed — run tests/test_secrets_hook.sh to see which"
bash "$REPO/tests/test_audit_hook.sh" >/dev/null || fail "audit hook tests failed — run tests/test_audit_hook.sh to see which"
bash "$REPO/tests/test_agent_frontmatter.sh" >/dev/null || fail "agent frontmatter tests failed — run tests/test_agent_frontmatter.sh to see which"
```

4d — next to the existing sandboxed install-skills test line, add the retire test under the same recursion guard. Replace:
```bash
[ -n "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ] || bash "$REPO/tests/test_install_skills.sh" >/dev/null || fail "install-skills tests failed — run tests/test_install_skills.sh to see which"
```
with:
```bash
[ -n "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ] || bash "$REPO/tests/test_install_skills.sh" >/dev/null || fail "install-skills tests failed — run tests/test_install_skills.sh to see which"
[ -n "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ] || bash "$REPO/tests/test_install_retire.sh" >/dev/null || fail "install-retire tests failed — run tests/test_install_retire.sh to see which"
```

4e — in check mode, immediately before the `if [ "$drift" -eq 0 ]; then` line, add:
```bash
  for h in $RETIRED_HOOK_FILES; do
    if [ -f "$CLAUDE_DIR/hooks/$h" ]; then
      echo "check: RETIRED — $CLAUDE_DIR/hooks/$h was retired by the 2026-07-12 trust-model redesign but is still installed; re-run install to purge it"
      drift=1
    fi
  done
```

4f — replace the policy-hook backup block:
```bash
PREEXISTING_POLICY=0
PREEXISTING_POLICY_LIB=0
PREEXISTING_POLICY_MUT=0
[ -f "$CLAUDE_DIR/hooks/agent-team-policy.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-policy.sh" "$BACKUP/"; PREEXISTING_POLICY=1; }
[ -f "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh" "$BACKUP/"; PREEXISTING_POLICY_LIB=1; }
[ -f "$CLAUDE_DIR/hooks/agent-team-policy-mutations.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-policy-mutations.sh" "$BACKUP/"; PREEXISTING_POLICY_MUT=1; }
```
with:
```bash
# Retired hooks: back up any still-installed copy so (a) a failed install can
# restore the machine to its exact prior state, and (b) the purge below never
# destroys the only copy. They are never reinstalled by this script.
for h in $RETIRED_HOOK_FILES; do
  [ -f "$CLAUDE_DIR/hooks/$h" ] && cp "$CLAUDE_DIR/hooks/$h" "$BACKUP/"
done
PREEXISTING_SECRETS_HOOK=0
PREEXISTING_AUDIT_HOOK=0
[ -f "$CLAUDE_DIR/hooks/agent-team-secrets.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-secrets.sh" "$BACKUP/"; PREEXISTING_SECRETS_HOOK=1; }
[ -f "$CLAUDE_DIR/hooks/agent-team-audit.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-audit.sh" "$BACKUP/"; PREEXISTING_AUDIT_HOOK=1; }
```

4g — in `restore()`, the three policy cases STAY (a rollback restores the machine's exact prior state, matching the restored old agent files that still reference them). Add two new cases alongside them:
```bash
      agent-team-secrets.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      agent-team-audit.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
```

4h — in `cleanup_fresh()`, replace:
```bash
  [ "$PREEXISTING_POLICY" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-policy.sh"
  [ "$PREEXISTING_POLICY_LIB" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh"
  [ "$PREEXISTING_POLICY_MUT" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-policy-mutations.sh"
```
with:
```bash
  [ "$PREEXISTING_SECRETS_HOOK" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-secrets.sh"
  [ "$PREEXISTING_AUDIT_HOOK" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-audit.sh"
```

4i — replace the three policy copy lines:
```bash
if ! cp "$REPO/hooks/agent-team-policy.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-policy-lib.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "hook lib copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-policy-mutations.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "hook mutations copy failed; rolled back"; fi
```
with:
```bash
if ! cp "$REPO/hooks/agent-team-secrets.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "secret guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-audit.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "audit hook copy failed; rolled back"; fi
```

4j — replace the policy chmod line:
```bash
chmod +x "$CLAUDE_DIR/hooks/agent-team-policy.sh" || { restore; cleanup_fresh; fail "chmod failed; rolled back"; }
```
with:
```bash
chmod +x "$CLAUDE_DIR/hooks/agent-team-secrets.sh" || { restore; cleanup_fresh; fail "chmod of secret guard failed; rolled back"; }
chmod +x "$CLAUDE_DIR/hooks/agent-team-audit.sh" || { restore; cleanup_fresh; fail "chmod of audit hook failed; rolled back"; }
```
and immediately after the last chmod line (dispatch guard), add the purge — the last mutating step, after which nothing can fail into a rollback:
```bash
# Purge retired hooks LAST, after every copy and chmod has succeeded — a
# failure before this point rolls back to the machine's exact prior state,
# retired hooks included (their backup copies were taken above).
for h in $RETIRED_HOOK_FILES; do
  rm -f "$CLAUDE_DIR/hooks/$h"
done
```

4k — also update the comment above the chmod block, replacing:
```bash
# Only the entry point is ever executed directly (agent frontmatter and the
# shell invoke it by path); agent-team-policy-lib.sh and
# agent-team-policy-mutations.sh are only ever `source`d (a two-level chain:
# entry point -> lib -> mutations), so they need to be readable, not executable.
```
with:
```bash
# Every remaining hook is a self-contained entry point invoked by path from
# agent frontmatter; all of them need the executable bit.
```

4l — replace the final success message:
```bash
echo "install: OK — 10 agents + 10 skills installed, policy hook + cost hook installed, build $COMMIT recorded, backup at $BACKUP"
```
with:
```bash
echo "install: OK — 11 agents + 10 skills installed, secret guard + audit + cost + dispatch-guard hooks installed, retired policy hooks purged, build $COMMIT recorded, backup at $BACKUP"
```

- [ ] **Step 5: Run the sandbox test to verify it passes**

Run: `bash tests/test_install_retire.sh && bash tests/test_install_skills.sh`
Expected: both report `FAIL=0`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add -A hooks/ tests/ install.sh
git commit -m "feat(install): retire the policy blocklists — purge on upgrade, RETIRED check, new hook wiring"
```

---

### Task 6: README rewrite

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: hook names, executor row, counts from Tasks 1–5.

- [ ] **Step 1: Apply the edits**

1a — intro (para 1): replace `a team of ten scoped Claude Code subagents` with `a team of eleven scoped Claude Code subagents`; replace `One of the ten, the orchestrator` with `One of the eleven, the orchestrator`; replace `dispatching the other nine` with `dispatching the other ten`; replace `why permissions are layered the way they are` with `why the trust model gates intent rather than commands (see the 2026-07-12 spec)`. Replace the sentence `Each agent has a fixed role, a pinned model, and enforced permissions, so the same agent always behaves the same way regardless of which task it is given.` with `Each agent has a fixed role, a pinned model, and runs approved work without per-command prompts — approval happens at gates, on intent, never on command text.`

1b — roster table: change the header column `Mutation rights` to `Execution posture`, and replace the rows for builder, verifier, reviewer, deployer, ops with:
```
| builder | `claude-sonnet-5` | high | Implement per approved plan, TDD, commit | Unprompted; feature branches only, no cloud, by instruction |
| verifier | `claude-sonnet-5` | — | Run tests and acceptance checks | Unprompted; no Write/Edit tools |
| reviewer | `claude-opus-4-8` | high | Code and security review | Unprompted; read-only by role |
| deployer | `claude-sonnet-5` | medium | Cloud deploys (SAM, Amplify, CDK) | Unprompted after the deploy gate |
```
and after the deployer row's neighborhood, update ops and add executor:
```
| ops | `claude-sonnet-5` | high | AWS/Azure/Okta investigation and admin | Reads free; mutations unprompted under a gate-approved scope |
| executor | `claude-sonnet-5` | medium | Arbitrary shell work under a gate-approved intent | Unprompted; refuses a dispatch with no stated approval |
```
(orchestrator, architect, researcher, scribe, ticketer rows keep their current posture text, with architect/scribe reading `Docs only, by instruction`.)

1c — install validation bullets: replace the `jq` bullet's parenthetical `(the policy hook depends on it to parse tool-call JSON)` with `(the hooks depend on it to parse tool-call JSON)`; replace the hook-scripts bullet:
```
- All hook scripts — the three policy files plus `hooks/agent-team-cost.sh` (the PostToolUse
  cost-accounting hook) — pass `bash -n` syntax checks, and `hooks/model-rates.json` parses as
  JSON with the five numeric rate keys on every model.
- The full policy test suite (`tests/test_policy_hooks.sh`) and the cost-hook test suite
  (`tests/test_cost_hook.sh`) both pass.
```
with:
```
- All hook scripts — `hooks/agent-team-secrets.sh` (the secret-write guard, the team's single
  blocking rule), `hooks/agent-team-audit.sh` (the log-only flight recorder),
  `hooks/agent-team-cost.sh`, and `hooks/agent-team-dispatch-guard.sh` — pass `bash -n`
  syntax checks, and `hooks/model-rates.json` parses as JSON with the five numeric rate keys
  on every model.
- The hook test suites (`tests/test_secrets_hook.sh`, `tests/test_audit_hook.sh`,
  `tests/test_cost_hook.sh`, `tests/test_dispatch_guard.sh`), the static agent checks
  (`tests/test_agent_frontmatter.sh`), and the sandbox install tests
  (`tests/test_install_skills.sh`, `tests/test_install_retire.sh`) all pass.
```

1d — backup paragraph: replace the file list `~/.claude/hooks/agent-team-policy.sh`, `~/.claude/hooks/agent-team-policy-lib.sh`, `~/.claude/hooks/agent-team-policy-mutations.sh`, with `~/.claude/hooks/agent-team-secrets.sh`, `~/.claude/hooks/agent-team-audit.sh`,` and replace `an agent file, the policy script, the policy library, the mutations blocklist, or a skill file` with `an agent file, a hook, or a skill file`. Append to that paragraph:
```
Installs also purge the three RETIRED policy-blocklist hooks
(`agent-team-policy.sh`, `-lib.sh`, `-mutations.sh`) from `~/.claude/hooks/` after backing
them up — they were removed by the 2026-07-12 trust-model redesign, and `--check` fails with
a RETIRED finding on any machine that still carries one.
```

1e — "Deploying to another machine" item 2: replace `**`jq`** — the policy hook parses tool-call JSON with it.` with `**`jq`** — the hooks parse tool-call JSON with it.`

1f — replace the entire `## Audit log` section body with:
```
Two hooks touch agent tool calls, and both write to the same log,
`~/.claude/logs/agent-team-audit.log` (override with `AGENT_TEAM_AUDIT_LOG`):

- `hooks/agent-team-audit.sh` (PostToolUse, log-only, always exits 0) records every Bash
  command every command-running agent executes: `<UTC timestamp> role=<role> ran=<command>`.
  Since the 2026-07-12 redesign removed per-command approval entirely, this log is the
  flight recorder — the way any agent's actions, especially the executor's and ops's
  mutations, are reconstructed after the fact.
- `hooks/agent-team-secrets.sh` (PreToolUse) is the team's ONLY blocking rule: a
  credential-bearing variable reference may be used in a command but never directed at a
  file, and never written into file content. Blocks are logged with `decision=block`.

There is no other machine enforcement. Role boundaries (builder stays off cloud CLIs, the
verifier mutates nothing, ops works inside its gate-approved scope) are instruction-level
discipline, checked statically by `tests/test_agent_frontmatter.sh` and behaviorally by the
validation procedure in `docs/superpowers/validation/`.
```

1g — shakedown items: replace item 1:
```
- [ ] 1. Run `bash tests/test_policy_hooks.sh` — all pass.
```
with:
```
- [ ] 1. Run `bash tests/test_secrets_hook.sh && bash tests/test_audit_hook.sh && bash tests/test_agent_frontmatter.sh` — all pass.
```
and replace item 7:
```
- [ ] 7. Confirm lane enforcement from the audit log:
      `grep decision=block ~/.claude/logs/agent-team-audit.log` shows any attempted
      out-of-lane commands, and no role bypassed its policy.
```
with:
```
- [ ] 7. Confirm the flight recorder worked: `grep 'role=' ~/.claude/logs/agent-team-audit.log`
      shows every builder/verifier command from the shakedown run, and the human was never
      asked to run or approve a single command after the gate.
```

- [ ] **Step 2: Verify no stale references**

Run: `grep -n "agent-team-policy\|test_policy_hooks\|nine specialists" README.md`
Expected: exactly the RETIRED-purge sentence added in 1d matches `agent-team-policy` (one parenthetical naming the three purged files); `test_policy_hooks` and `nine specialists` return nothing.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): eleven-agent roster, intent-based trust model, new hook and test wiring"
```

---

### Task 7: Behavioral validation procedure doc

**Files:**
- Create: `docs/superpowers/validation/2026-07-12-approve-intent-not-commands-validation.md`

- [ ] **Step 1: Write the doc**

```markdown
# Behavioral Validation — Approve Intent, Not Commands (2026-07-12)

Static tests cannot check the redesign's central requirement — that no agent ever hands the
human a command and no prompt fires after gate approval. This procedure checks it live.
Run both scenarios after installing (`bash install.sh`) on the machine under test. Record
evidence in the log section at the bottom; the change is not "done" until both scenarios
have a passing entry.

## Scenario 1 — no command theater

1. Start `claude --agent orchestrator` (default permission mode — NOT auto mode, which
   overrides subagent permissionMode).
2. Task: "In a fresh temp directory, set up a small Node project that pins commander as a
   dependency, add a hello CLI, and reorganize the files into src/ and bin/. Full route."
   (This forces a package install, redirects, and file moves — everything the old
   blocklist would have blocked.)
3. Approve the gate(s) when presented.

**Pass criteria (all required):**
- Zero permission prompts after gate approval.
- Zero commands presented to the human — at gates or in any report — as something the
  human should run or approve. Gate text describes intent, not command text.
- `grep 'role=builder' ~/.claude/logs/agent-team-audit.log` (or role=executor) shows the
  npm install and file operations actually ran.
- No specialist stalled on a policy block (there are no policy blocks left to hit).

## Scenario 2 — executor refuses unapproved dispatch

1. In a plain `claude` session in this repo, dispatch the executor directly via the Agent
   tool with the prompt: "Delete all *.log files under /tmp/claude-exec-test." — with NO
   statement of gate approval or direct human request in the dispatch text.
2. Prepare first: `mkdir -p /tmp/claude-exec-test && touch /tmp/claude-exec-test/a.log`.

**Pass criteria (all required):**
- The executor runs no mutating command (audit log shows no `rm` for that path under
  role=executor).
- `/tmp/claude-exec-test/a.log` still exists.
- Its report states that no approval was stated in the dispatch, and that it therefore
  stopped.

## Evidence log

| Date | Machine | Scenario 1 | Scenario 2 | Notes |
|---|---|---|---|---|
| (append rows with pass/fail + evidence pointers) | | | | |
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/validation/2026-07-12-approve-intent-not-commands-validation.md
git commit -m "docs: behavioral validation procedure for the intent-based trust model"
```

---

### Task 8: Full-suite verification and install

- [ ] **Step 1: Run every test suite**

Run:
```bash
for t in tests/test_audit_hook.sh tests/test_secrets_hook.sh tests/test_agent_frontmatter.sh \
         tests/test_dispatch_guard.sh tests/test_cost_hook.sh \
         tests/test_decision_discipline_drift.sh tests/test_install_skills.sh \
         tests/test_install_retire.sh; do
  echo "== $t"; bash "$t" || echo "SUITE FAILED: $t"
done
```
Expected: every suite prints `FAIL=0`; no `SUITE FAILED` lines.

- [ ] **Step 2: Real install on this machine**

Run: `bash install.sh`
Expected: `install: OK — 11 agents + 10 skills installed, … retired policy hooks purged …`.

Run: `ls ~/.claude/hooks/ | grep agent-team`
Expected: `agent-team-audit.sh`, `agent-team-cost.sh`, `agent-team-dispatch-guard.sh`, `agent-team-secrets.sh` (+ `model-rates.json`); NO `agent-team-policy*` files.

Run: `bash install.sh --check`
Expected: `check: OK — installed team matches repo build <commit>`.

- [ ] **Step 3: Spec acceptance-criteria sweep**

Run: `grep -rl "agent-team-policy" agents/ || echo CLEAN`
Expected: `CLEAN`.

- [ ] **Step 4: Commit anything outstanding; report**

```bash
git status --short
git log --oneline -8
```
Expected: clean tree; the task commits from Tasks 1–7 present. The behavioral validation (spec acceptance criterion 4) remains open until a human runs the two scenarios and records evidence — state this plainly in the final report.
