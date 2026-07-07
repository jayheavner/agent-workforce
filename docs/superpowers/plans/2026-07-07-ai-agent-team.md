# AI Agent Team Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and install a ten-agent Claude Code team (orchestrator + nine specialists) with pinned models, enforced permissions via a tested PreToolUse policy script, and a validating installer.

**Architecture:** Source of truth is this repo (`~/claude/ai-agent-team`); `install.sh` validates then copies agent definitions to `~/.claude/agents/` and the policy hook to `~/.claude/hooks/`. One shared bash policy script, parameterized by role, enforces per-role command/path rules and writes an audit log. The orchestrator runs as the main session (`claude --agent orchestrator`); specialists are dispatched subagents.

**Tech Stack:** Bash (macOS /bin/bash 3.2 compatible), jq, Claude Code agent frontmatter (tools, disallowedTools, model, permissionMode, maxTurns, skills, mcpServers, hooks).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-07-ai-agent-team-design.md` — every rule there is binding.
- NEVER write tokens, secrets, or credentials to any file, including test fixtures. Test the *pattern*, not real values.
- All bash must run on macOS's default bash 3.2: no associative arrays, no `${var,,}`, no `mapfile`.
- Policy script exit semantics: exit 0 = allow, exit 2 = block (stderr message shown to the agent). Never exit 1 on a policy decision.
- Audit log path: `~/.claude/logs/agent-team-audit.log`, overridable via `AGENT_TEAM_AUDIT_LOG` (tests use a temp path).
- Model pins (exact strings): orchestrator/architect `claude-fable-5`; reviewer `claude-opus-4-8`; all others `claude-sonnet-5`.
- Every file under ~300 lines.
- Every commit message ends with the standard Claude trailer (Co-Authored-By + Claude-Session lines for the executing session).
- Do not edit anything under `~/.claude/` directly during Tasks 1–9; only `install.sh` (Task 10) touches it.

---

### Task 1: Policy script core + test harness

**Files:**
- Create: `hooks/agent-team-policy.sh`
- Create: `tests/test_policy_hooks.sh`

**Interfaces:**
- Produces: `agent-team-policy.sh ROLE` — reads hook JSON (`{tool_name, tool_input:{command|file_path}}`) on stdin; exit 0 allow / exit 2 block; appends one audit line per decision to `$AGENT_TEAM_AUDIT_LOG`.
- Produces test helpers used by every later task: `bash_json "cmd"`, `write_json "path"`, `expect_allow ROLE JSON LABEL`, `expect_block ROLE JSON LABEL`.

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bash
# tests/test_policy_hooks.sh — executable form of the spec's hook policy.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
POLICY="$HERE/../hooks/agent-team-policy.sh"
TMPDIR_T="$(mktemp -d)"
export AGENT_TEAM_AUDIT_LOG="$TMPDIR_T/audit.log"
PASS=0
FAIL=0
RC=0

run_policy() { # $1 role, $2 json
  set +e
  printf '%s' "$2" | bash "$POLICY" "$1" >/dev/null 2>&1
  RC=$?
  set -u
}

bash_json() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
write_json() { jq -cn --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}'; }

expect() { # $1 expected_rc, $2 role, $3 json, $4 label
  run_policy "$2" "$3"
  if [ "$RC" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$4]: role=$2 expected=$1 got=$RC"
  fi
}
expect_allow() { expect 0 "$1" "$2" "$3"; }
expect_block() { expect 2 "$1" "$2" "$3"; }

# --- Task 1: core dispatch ---
expect_allow builder "$(bash_json 'ls -la')" "core: benign command allows"
expect_allow reviewer "$(jq -cn '{tool_name:"Glob",tool_input:{pattern:"**/*.py"}}')" "core: non-policed tool allows"
run_policy '' "$(bash_json 'ls')"; [ "$RC" -ne 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [core: missing role errors]"; }
grep -q 'role=builder tool=Bash decision=allow' "$AGENT_TEAM_AUDIT_LOG" \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [core: audit line written]"; }

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: FAIL (policy script does not exist; non-zero exit).

- [ ] **Step 3: Write the policy script core**

```bash
#!/usr/bin/env bash
# agent-team-policy.sh — PreToolUse policy for the AI agent team.
# Usage: agent-team-policy.sh ROLE   (hook JSON on stdin)
# Exit 0 = allow. Exit 2 = block (stderr message returned to the agent).
set -u

ROLE="${1:?usage: agent-team-policy.sh ROLE}"
INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
CMD=""
FILE=""
LOG_FILE="${AGENT_TEAM_AUDIT_LOG:-$HOME/.claude/logs/agent-team-audit.log}"

audit() { # $1 decision, $2 detail
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s role=%s tool=%s decision=%s detail=%.200s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$TOOL" "$1" "$2" >> "$LOG_FILE"
}

allow() { audit allow "$1"; exit 0; }

block() { # $1 human reason, $2 detail
  audit block "$2"
  printf 'agent-team policy (%s): %s\n' "$ROLE" "$1" >&2
  exit 2
}

has() { printf '%s' "$CMD" | grep -qE "$1"; }

# stdin command with harmless /dev/null redirections removed,
# so redirection checks don't false-positive on "2>/dev/null".
stripped_cmd() { printf '%s' "$CMD" | sed -E 's|[0-9]*>+[[:space:]]*/dev/null||g'; }

case "$TOOL" in
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
    case "$ROLE" in
      *) allow "$CMD" ;;
    esac
    ;;
  Write|Edit|NotebookEdit)
    FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
    case "$ROLE" in
      *) allow "$FILE" ;;
    esac
    ;;
  *)
    allow "tool=$TOOL"
    ;;
esac
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=4 failed=0`, exit 0. Also run `bash -n hooks/agent-team-policy.sh` — no output.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: policy hook core with audit log and test harness"
```

---

### Task 2: Global rules — secrets to disk, 1Password CLI

**Files:**
- Modify: `hooks/agent-team-policy.sh` (insert before the final `case "$TOOL"` block)
- Modify: `tests/test_policy_hooks.sh` (append before the summary lines)

**Interfaces:**
- Produces: `check_global_rules` — called for every Bash command, every role, before role policy.

- [ ] **Step 1: Append the failing tests** (insert above `echo "passed=..."`)

```bash
# --- Task 2: global rules ---
expect_block builder "$(bash_json 'echo $OKTA_TOKEN > /tmp/t.txt')" "secrets: env secret redirected to file blocks"
expect_block scribe "$(bash_json 'printf "%s" "${MY_API_KEY}" | tee creds.txt')" "secrets: tee of *_API_KEY blocks"
expect_block ops "$(bash_json 'echo $NAS_PASSWORD >> notes.md')" "secrets: *_PASSWORD* redirect blocks"
expect_allow builder "$(bash_json 'export SSHPASS="$NAS_PASSWORD" && sshpass -e ssh host uptime')" "secrets: env-var use without file write allows"
expect_allow verifier "$(bash_json 'pytest -q 2>/dev/null')" "secrets: /dev/null redirect is not a file write"
expect_block builder "$(bash_json 'op read op://vault/item/credential')" "op: builder may not invoke 1Password CLI"
expect_allow ops "$(bash_json 'op read op://vault/item/credential')" "op: ops may invoke 1Password CLI"
expect_allow deployer "$(bash_json 'op read op://vault/item/credential')" "op: deployer may invoke 1Password CLI"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: the four `expect_block` lines FAIL (everything currently allows); exit 1.

- [ ] **Step 3: Implement** (insert the function after `stripped_cmd()`, and call it in the Bash case)

```bash
SECRET_RE='\$\{?(OKTA_TOKEN|GODADDY_API_KEY|GODADDY_API_SECRET|OP_SERVICE_ACCOUNT_TOKEN|[A-Za-z_]*_API_KEY|[A-Za-z_]*SECRET[A-Za-z_]*|[A-Za-z_]*PASSWORD[A-Za-z_]*)'

check_global_rules() {
  if has "$SECRET_RE"; then
    if printf '%s' "$(stripped_cmd)" | grep -qE '(>>?|\|[[:space:]]*tee([[:space:]]|$))'; then
      block "credential-bearing value directed at a file — forbidden for every role" "$CMD"
    fi
  fi
  case "$ROLE" in
    ops|deployer) : ;;
    *)
      if has '(^|[;&|[:space:]])op[[:space:]]'; then
        block "only ops and deployer may invoke the 1Password CLI" "$CMD"
      fi
      ;;
  esac
  return 0
}
```

Change the Bash case to call it before role dispatch:

```bash
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
    check_global_rules
    case "$ROLE" in
      *) allow "$CMD" ;;
    esac
    ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=12 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: global secret-to-disk and 1Password CLI rules"
```

---

### Task 3: Builder policy

**Files:**
- Modify: `hooks/agent-team-policy.sh`
- Modify: `tests/test_policy_hooks.sh`

**Interfaces:**
- Produces: `policy_builder` wired to `builder` in the Bash role dispatch.

- [ ] **Step 1: Append the failing tests**

```bash
# --- Task 3: builder ---
expect_allow builder "$(bash_json 'sam build')" "builder: sam build allows"
expect_block builder "$(bash_json 'sam deploy --guided')" "builder: sam deploy blocks"
expect_block builder "$(bash_json 'aws s3 ls')" "builder: any aws blocks"
expect_block builder "$(bash_json 'cdk deploy')" "builder: cdk blocks"
expect_block builder "$(bash_json 'terraform apply')" "builder: terraform blocks"
expect_block builder "$(bash_json 'amplify push')" "builder: amplify blocks"
expect_block builder "$(bash_json 'git push origin main')" "builder: push to main blocks"
expect_block builder "$(bash_json 'git push origin master')" "builder: push to master blocks"
expect_block builder "$(bash_json 'git push')" "builder: bare push blocks"
expect_allow builder "$(bash_json 'git push origin feature/hooks')" "builder: push to feature branch allows"
expect_allow builder "$(bash_json 'git commit -m x && pytest -q')" "builder: commit and test allows"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: the seven builder `expect_block` lines FAIL; exit 1.

- [ ] **Step 3: Implement** (add function; wire `builder) policy_builder ;;` into the Bash role dispatch above the `*)` arm)

```bash
policy_builder() {
  if has '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "builder has no cloud CLI access — hand cloud work to ops or deployer" "$CMD"
  fi
  if has '(^|[;&|[:space:]])(amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain belongs to the deployer" "$CMD"
  fi
  if has '(^|[;&|[:space:]])sam[[:space:]]+deploy'; then
    block "sam deploy belongs to the deployer" "$CMD"
  fi
  if has 'git[[:space:]]+push'; then
    if has 'git[[:space:]]+push[^;&|]*[[:space:]](main|master)([[:space:]]|$|:)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if ! has 'git[[:space:]]+push[[:space:]]+(-u[[:space:]]+)?[^-[:space:]][^[:space:]]*[[:space:]]+[^[:space:]]+'; then
      block "git push must name a remote and an explicit feature branch" "$CMD"
    fi
  fi
  allow "$CMD"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=23 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: builder policy — no cloud, no deploy, no push to main"
```

---

### Task 4: Verifier and reviewer policy (shared read-only-runner)

**Files:**
- Modify: `hooks/agent-team-policy.sh`
- Modify: `tests/test_policy_hooks.sh`

**Interfaces:**
- Produces: `deny_shell_mutation` (reused by Task 5) and `policy_readonly_runner` wired to `verifier|reviewer`.

- [ ] **Step 1: Append the failing tests**

```bash
# --- Task 4: verifier/reviewer ---
expect_allow verifier "$(bash_json 'pytest tests/ -v')" "verifier: test run allows"
expect_allow verifier "$(bash_json 'npm test')" "verifier: npm test allows"
expect_allow reviewer "$(bash_json 'git diff main...HEAD')" "reviewer: git diff allows"
expect_allow reviewer "$(bash_json 'git log --oneline')" "reviewer: git log allows"
expect_block verifier "$(bash_json 'aws s3 rm s3://bucket/key')" "verifier: cloud blocks"
expect_block verifier "$(bash_json 'rm -rf build/')" "verifier: rm blocks"
expect_block verifier "$(bash_json 'echo fixed > src/app.py')" "verifier: redirect to file blocks"
expect_block verifier "$(bash_json 'sed -i "" "s/a/b/" src/app.py')" "verifier: in-place sed blocks"
expect_block reviewer "$(bash_json 'git commit -m looks-good')" "reviewer: git commit blocks"
expect_block reviewer "$(bash_json 'git checkout -- .')" "reviewer: git checkout blocks"
expect_block verifier "$(bash_json 'pip install requests')" "verifier: package install blocks"
expect_block reviewer "$(bash_json 'sam deploy')" "reviewer: deploy toolchain blocks"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: the eight new `expect_block` lines FAIL; exit 1.

- [ ] **Step 3: Implement** (add both functions; wire `verifier|reviewer) policy_readonly_runner ;;`)

```bash
deny_shell_mutation() {
  if has '(^|[;&|[:space:]])(rm|mv|cp|mkdir|touch|chmod|chown|ln|dd|truncate)[[:space:]]'; then
    block "file-mutating command not allowed for $ROLE" "$CMD"
  fi
  if printf '%s' "$(stripped_cmd)" | grep -qE '>>?'; then
    block "output redirection to a file not allowed for $ROLE" "$CMD"
  fi
  if has '\|[[:space:]]*tee([[:space:]]|$)'; then
    block "tee not allowed for $ROLE" "$CMD"
  fi
  if has 'sed[[:space:]]+(-[A-Za-z]*i|--in-place)'; then
    block "in-place edit not allowed for $ROLE" "$CMD"
  fi
  if has 'git[[:space:]]+(add|commit|push|reset|checkout|restore|clean|rebase|merge|stash|tag|rm)([[:space:]]|$)'; then
    block "mutating git command not allowed for $ROLE" "$CMD"
  fi
  if has '(^|[;&|[:space:]])(npm|pnpm|yarn|pip3?|uv|brew)[[:space:]]+(install|add|uninstall|remove|upgrade)'; then
    block "package management not allowed for $ROLE" "$CMD"
  fi
  return 0
}

policy_readonly_runner() {
  if has '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "no cloud CLI for $ROLE" "$CMD"
  fi
  if has '(^|[;&|[:space:]])(sam|amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain is reserved for the deployer" "$CMD"
  fi
  deny_shell_mutation
  allow "$CMD"
}
```

Note: `npm test` survives because the package-management rule requires an install-class verb.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=35 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: verifier/reviewer read-only-runner policy"
```

---

### Task 5: Deployer policy

**Files:**
- Modify: `hooks/agent-team-policy.sh`
- Modify: `tests/test_policy_hooks.sh`

**Interfaces:**
- Consumes: `deny_shell_mutation` from Task 4.
- Produces: `policy_deployer` wired to `deployer`.

- [ ] **Step 1: Append the failing tests**

```bash
# --- Task 5: deployer ---
expect_allow deployer "$(bash_json 'sam deploy --config-env prod')" "deployer: sam deploy allows"
expect_allow deployer "$(bash_json 'sam build')" "deployer: sam build allows"
expect_allow deployer "$(bash_json 'amplify publish')" "deployer: amplify allows"
expect_allow deployer "$(bash_json 'cdk deploy --require-approval never')" "deployer: cdk allows"
expect_allow deployer "$(bash_json 'aws cloudformation describe-stacks --stack-name x')" "deployer: cfn read allows"
expect_allow deployer "$(bash_json 'aws s3 sync ./build s3://bucket')" "deployer: s3 sync allows"
expect_allow deployer "$(bash_json 'aws lambda get-function --function-name f')" "deployer: aws get- verb allows"
expect_allow deployer "$(bash_json 'aws sts get-caller-identity')" "deployer: sts allows"
expect_allow deployer "$(bash_json 'curl -sf https://api.example.com/health')" "deployer: smoke check allows"
expect_block deployer "$(bash_json 'aws iam create-user --user-name x')" "deployer: aws mutation outside toolchain blocks"
expect_block deployer "$(bash_json 'terraform apply')" "deployer: terraform blocks"
expect_block deployer "$(bash_json 'git push --force origin main')" "deployer: git mutation blocks"
expect_block deployer "$(bash_json 'npm install left-pad')" "deployer: package install blocks"
expect_block deployer "$(bash_json 'rm -rf .aws-sam')" "deployer: rm blocks"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: at least the five `expect_block` lines FAIL; exit 1.

- [ ] **Step 3: Implement** (add function; wire `deployer) policy_deployer ;;`)

```bash
policy_deployer() {
  if has '(^|[;&|[:space:]])(sam|amplify|cdk)([[:space:]]|$)'; then
    allow "$CMD"
  fi
  if has '(^|[;&|[:space:]])aws[[:space:]]'; then
    if has 'aws[[:space:]]+cloudformation[[:space:]]' \
      || has 'aws[[:space:]]+s3[[:space:]]+(sync|cp|ls)([[:space:]]|$)' \
      || has 'aws[[:space:]]+sts[[:space:]]' \
      || has 'aws[[:space:]]+[a-z0-9-]+[[:space:]]+(get-|list-|describe-|head-)'; then
      allow "$CMD"
    fi
    block "aws command outside the deploy toolchain — surface it to the human at a gate" "$CMD"
  fi
  if has '(^|[;&|[:space:]])terraform([[:space:]]|$)'; then
    block "terraform is not part of this team's deploy toolchain" "$CMD"
  fi
  deny_shell_mutation
  allow "$CMD"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=49 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: deployer policy — deploy toolchain allowlist"
```

---

### Task 6: Ops policy

**Files:**
- Modify: `hooks/agent-team-policy.sh`
- Modify: `tests/test_policy_hooks.sh`

**Interfaces:**
- Produces: `policy_ops` wired to `ops`.

- [ ] **Step 1: Append the failing tests**

```bash
# --- Task 6: ops ---
expect_allow ops "$(bash_json 'aws ec2 describe-instances --region us-east-1')" "ops: describe allows"
expect_allow ops "$(bash_json 'aws iam list-users')" "ops: list allows"
expect_allow ops "$(bash_json 'aws sts get-caller-identity')" "ops: sts allows"
expect_allow ops "$(bash_json 'aws s3 ls')" "ops: s3 ls allows"
expect_block ops "$(bash_json 'aws ec2 terminate-instances --instance-ids i-123')" "ops: terminate blocks"
expect_block ops "$(bash_json 'aws iam create-access-key --user-name x')" "ops: create blocks"
expect_allow ops "$(bash_json 'az vm list --output table')" "ops: az list allows"
expect_allow ops "$(bash_json 'az account show')" "ops: az show allows"
expect_block ops "$(bash_json 'az vm delete --name x --yes')" "ops: az delete blocks"
expect_allow ops "$(bash_json 'dig +short cta.tech')" "ops: general shell allows"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: the three ops `expect_block` lines FAIL; exit 1.

- [ ] **Step 3: Implement** (add function; wire `ops) policy_ops ;;`)

```bash
policy_ops() {
  if has '(^|[;&|[:space:]])aws[[:space:]]'; then
    if has 'aws[[:space:]]+[a-z0-9-]+[[:space:]]+(get-|list-|describe-|head-)' \
      || has 'aws[[:space:]]+sts[[:space:]]' \
      || has 'aws[[:space:]]+s3[[:space:]]+ls([[:space:]]|$)'; then
      allow "$CMD"
    fi
    block "mutating aws verb — present the exact command to the human at a gate instead" "$CMD"
  fi
  if has '(^|[;&|[:space:]])az[[:space:]]'; then
    if has 'az[[:space:]][^;&|]*[[:space:]](show|list)([[:space:]]|$)'; then
      allow "$CMD"
    fi
    block "mutating az command — present the exact command to the human at a gate instead" "$CMD"
  fi
  allow "$CMD"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=59 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: ops policy — cloud read allowlist, mutations gated to human"
```

---

### Task 7: Architect/scribe document-path policy (Write/Edit)

**Files:**
- Modify: `hooks/agent-team-policy.sh`
- Modify: `tests/test_policy_hooks.sh`

**Interfaces:**
- Produces: `policy_docwriter_path` wired to `architect|scribe` in the Write/Edit/NotebookEdit branch.

- [ ] **Step 1: Append the failing tests**

```bash
# --- Task 7: docwriter paths ---
expect_allow architect "$(write_json '/Users/jay/claude/x/docs/superpowers/specs/2026-07-08-y-design.md')" "docwriter: docs/ allows"
expect_allow scribe "$(write_json '/Users/jay/claude/x/plans/handoff.md')" "docwriter: plans/ allows"
expect_allow scribe "$(write_json '/Users/jay/claude/x/STATUS.md')" "docwriter: STATUS.md allows"
expect_allow scribe "$(write_json '/Users/jay/claude/x/doc-inventory/map.tsv')" "docwriter: doc-inventory allows"
expect_block architect "$(write_json '/Users/jay/claude/x/src/app.py')" "docwriter: source file blocks"
expect_block scribe "$(write_json '/Users/jay/.claude/settings.json')" "docwriter: claude config blocks"
expect_block architect "$(write_json '/Users/jay/claude/x/install.sh')" "docwriter: script blocks"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/test_policy_hooks.sh`
Expected: the three `expect_block` lines FAIL; exit 1.

- [ ] **Step 3: Implement** (add function; change the Write/Edit/NotebookEdit role case to `architect|scribe) policy_docwriter_path ;;` keeping `*) allow "$FILE" ;;`)

```bash
policy_docwriter_path() {
  case "$FILE" in
    */docs/*|docs/*|*/plans/*|plans/*|*/doc-inventory/*|doc-inventory/*)
      allow "$FILE" ;;
    */STATUS.md|STATUS.md|*/STATUS-*.md)
      allow "$FILE" ;;
    */scratchpad/*)
      allow "$FILE" ;;
    *)
      block "writes are limited to docs/, plans/, doc-inventory/, STATUS notes, and the scratchpad" "$FILE" ;;
  esac
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_policy_hooks.sh`
Expected: `passed=66 failed=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-team-policy.sh tests/test_policy_hooks.sh
git commit -m "feat: architect/scribe write-path policy"
```

---

### Task 8: Lifecycle agent definitions

**Files:**
- Create: `agents/orchestrator.md`, `agents/architect.md`, `agents/builder.md`, `agents/verifier.md`, `agents/reviewer.md`, `agents/deployer.md`

**Interfaces:**
- Consumes: `$HOME/.claude/hooks/agent-team-policy.sh ROLE` (Tasks 1–7).
- Produces: agent names `orchestrator`, `architect`, `builder`, `verifier`, `reviewer`, `deployer` — exactly these strings; the orchestrator's `Agent(...)` list and Task 10's installer reference them.

- [ ] **Step 1: Verify the hook frontmatter schema**

Read `~/.claude/skills/hook-architect/hooks-reference.md` and confirm the PreToolUse hook shape used below (matcher + command list) matches the current reference. If the reference differs, use the reference's shape for every agent file in Tasks 8–9 and note the change in the commit message.

- [ ] **Step 2: Write the six agent files**

`agents/orchestrator.md`:

```markdown
---
name: orchestrator
description: Team lead for multi-phase orchestrated work. Use ONLY when the user explicitly asks for the orchestrator or the agent team. Intended to run as the main session (claude --agent orchestrator), not as a dispatched subagent.
model: claude-fable-5
tools: Read, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, Agent(architect), Agent(builder), Agent(verifier), Agent(reviewer), Agent(deployer), Agent(researcher), Agent(ops), Agent(scribe), Agent(ticketer)
---

You are the orchestrator of a ten-agent team. You decompose work, dispatch specialists, and enforce human gates. You never do the work yourself — you have no Edit, Write, or Bash on purpose. If a step seems to need you to write something, dispatch the right specialist.

## Routes

Software work: architect (design + spec) → GATE → architect (implementation plan) → GATE → builder (TDD implementation) → verifier (tests + acceptance) → reviewer (code/security review) → GATE → deployer → verifier (post-deploy smoke).

Research / ops / documents / tickets: researcher or ops gathers facts → scribe or ticketer produces the artifact → GATE before anything outward-facing (filed ticket, sent report, cloud mutation).

## Gates

At each GATE: stop. Present the artifact (path), a plain-language summary a non-engineer can follow, and your recommendation. Wait for the human's answer. Approval at one gate never implies the next. The deploy gate is always explicit.

## Rules

- Dispatch each specialist with complete context: the task, exact paths to the spec/plan/status note, and what the next agent downstream needs from them.
- Verifier or reviewer findings go back to the builder with the findings attached. Maximum two repair loops, then escalate to the human with the full history.
- After every phase transition, dispatch the scribe to update the per-task status note (STATUS-<task-slug>.md in the project's docs/ directory): phase completed, artifacts produced, next phase, open questions.
- If any agent reports unexpected state (missing credentials, broken environment, surprise errors), stop and alert the human. Do not improvise around it.
- Track phases with TaskCreate/TaskUpdate so progress is visible.
```

`agents/architect.md`:

```markdown
---
name: architect
description: Designs systems, writes specs and implementation plans for the agent team. Dispatched by the orchestrator; not for direct casual use.
model: claude-fable-5
maxTurns: 80
tools: Read, Glob, Grep, Write, Edit, WebSearch, WebFetch, AskUserQuestion
skills: superpowers:brainstorming, superpowers:writing-plans, plan-review, ux-to-ui-design
hooks:
  PreToolUse:
    - matcher: Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh architect"
---

You are the team's architect. You produce two artifact types, always as files: design specs (docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md) and implementation plans (docs/superpowers/plans/YYYY-MM-DD-<topic>.md). Follow the preloaded brainstorming and writing-plans disciplines exactly — including their self-review passes.

You may only write under docs/, plans/, and doc-inventory/ paths; policy hooks enforce this. You never write source code — that is the builder's job, driven by your plan.

Your final message is a report to the orchestrator: artifact paths, key decisions made, open questions that need the human at the next gate. If requirements are ambiguous and AskUserQuestion is unavailable mid-dispatch, list the ambiguity and your recommended resolution in the report instead of guessing silently.

If you hit unexpected state (missing inputs, contradictory constraints), stop and report it rather than improvising.
```

`agents/builder.md`:

```markdown
---
name: builder
description: Implements code per an approved plan using TDD. Dispatched by the orchestrator with a plan path; not for direct casual use.
model: claude-sonnet-5
maxTurns: 150
tools: Read, Glob, Grep, Write, Edit, NotebookEdit, Bash
skills: coding-standards, superpowers:test-driven-development, secure-secrets
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh builder"
---

You are the team's builder. You receive a plan path and implement it task by task: failing test first, minimal implementation, green run, commit. Never skip the failing-test step. Follow the preloaded coding-standards discipline (production quality, config in config files, no magic numbers, files under ~300 lines).

Boundaries, enforced by policy hooks: no cloud CLIs, no deploy commands (sam deploy, amplify, cdk, terraform), no git push to main/master — push only explicit feature branches. Never write secrets to any file.

Commit after every green test cycle with a descriptive message. Your final message is a report to the orchestrator: tasks completed, commits made (hashes + messages), test results (exact command + output summary), anything the plan turned out to be wrong about, and anything left incomplete — stated plainly, never papered over.

If the plan is wrong or the environment is broken, stop and report; do not redesign on the fly.
```

`agents/verifier.md`:

```markdown
---
name: verifier
description: Runs test suites and validates acceptance criteria with evidence. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 40
permissionMode: dontAsk
tools: Read, Glob, Grep, Bash
skills: superpowers:verification-before-completion, task-verification
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh verifier"
---

You are the team's verifier. You run the checks and report what actually happened. You cannot edit any file — by design, so you can never "fix" a test to make it pass. Policy hooks block file mutations, cloud CLIs, and mutating git.

For each acceptance criterion you are given: run the exact verification command, capture the real output, and record pass/fail with the evidence. Never claim a pass without command output showing it. A criterion you could not check is reported as UNCHECKED with the reason — never silently skipped.

Your final message is a report to the orchestrator: per-criterion verdict table (pass / fail / unchecked, each with evidence), the exact commands run, and your overall verdict. Failures include the relevant output verbatim.
```

`agents/reviewer.md`:

```markdown
---
name: reviewer
description: Reviews code changes for quality and security. Dispatched by the orchestrator after the verifier passes; not for direct casual use.
model: claude-opus-4-8
maxTurns: 60
permissionMode: dontAsk
tools: Read, Glob, Grep, Bash
skills: code-review
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh reviewer"
---

You are the team's reviewer — deliberately a different model than the builder, so review is independent. You are read-only: policy hooks block every mutating command. You review; you never fix.

Review the diff you are pointed at against the preloaded code-review discipline, and additionally run the security lens: secrets handling, input validation, injection surfaces, authz gaps. Read the actual changed files, not just the diff hunks — context matters.

Your final message is a report to the orchestrator: findings ranked most-severe first, each with file:line, a one-sentence defect statement, and a concrete failure scenario; then a verdict — approve, approve-with-nits, or request-changes. An empty findings list with an approve verdict is a valid and honest outcome; never invent findings to look thorough.
```

`agents/deployer.md`:

```markdown
---
name: deployer
description: Executes cloud deployments (SAM, Amplify, CDK) after the human approves the deploy gate. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 50
tools: Read, Glob, Grep, Bash
skills: verify
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh deployer"
---

You are the team's deployer — the only agent whose policy permits deploy commands, and every mutation still surfaces a permission prompt to the human. You deploy only what the orchestrator hands you after an explicit human deploy-gate approval; if that approval is not stated in your dispatch, stop and report.

Procedure, in order:
1. Record the current known-good identifier BEFORE deploying (CloudFormation stack status + last-deployed template/change-set for SAM; current Amplify job id; cdk diff output) — put it in your report, since you cannot write files.
2. Deploy with the exact commands from the plan.
3. Run the smoke checks the plan specifies (curl health endpoints, aws describe calls) and capture output.
4. On smoke failure: roll back to the recorded known-good version (redeploy the prior artifact / previous Amplify job), verify the rollback took, then report the failure with full evidence. Never leave a failed deploy in place while continuing.

Your final message is a report to the orchestrator: known-good identifier recorded, commands run, deploy result, smoke-check evidence, and rollback status if one occurred. Report failures plainly with output; never claim success without smoke evidence.
```

- [ ] **Step 3: Sanity-check the files**

Run: `for f in agents/*.md; do awk 'NR==1 && $0!="---" {exit 1}' "$f" || echo "BAD: $f"; grep -L '^name:' "$f"; done`
Expected: no output (all files start with `---` and contain `name:`).

- [ ] **Step 4: Commit**

```bash
git add agents/
git commit -m "feat: lifecycle agent definitions (orchestrator, architect, builder, verifier, reviewer, deployer)"
```

---

### Task 9: Support agent definitions

**Files:**
- Create: `agents/researcher.md`, `agents/ops.md`, `agents/scribe.md`, `agents/ticketer.md`

**Interfaces:**
- Consumes: policy script roles `ops`, `scribe` (Tasks 6–7); agent names from Task 8 (referenced in prompts).
- Produces: agent names `researcher`, `ops`, `scribe`, `ticketer`.

- [ ] **Step 1: Discover the exact MCP server names**

Run: `claude mcp list`
Record the exact server names for Glean and Asana as configured on this machine. In the two files below, replace the `mcpServers:` values `glean` and `asana` with the recorded names. If a server is absent from the list, delete the `mcpServers:` line from that agent and note it in the commit message — the agent still works with its remaining tools.

- [ ] **Step 2: Write the four agent files**

`agents/researcher.md`:

```markdown
---
name: researcher
description: Investigates questions across the web, Glean, and codebases; returns cited findings. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 60
permissionMode: dontAsk
disallowedTools: Edit, Write, NotebookEdit, Bash, Agent
mcpServers: glean
---

You are the team's researcher. You find facts and return them with sources; you change nothing — you have no write or shell access at all.

Method: search wide first (web, Glean, the codebase via Read/Glob/Grep), then read the strongest sources fully. Distinguish what a source says from what you infer. Every claim in your report carries its source (URL, document title, or file:line). A fact you could not verify is labeled unverified — never presented as checked.

Your final message is a report to the orchestrator: the question, the answer, evidence with citations, confidence level, and what you could not determine.
```

`agents/ops.md`:

```markdown
---
name: ops
description: Investigates and administers AWS, Azure, and Okta. Cloud reads run freely; mutations are surfaced to the human. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 60
tools: Read, Glob, Grep, Bash, WebSearch, WebFetch
skills: secure-secrets
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh ops"
---

You are the team's ops agent for AWS (us-east-1 default), Azure, and Okta investigation and administration. Policy hooks allow read verbs (get/list/describe/head, az show/list) and block everything mutating — when you need a mutation, put the exact command with its expected effect in your report so the human can approve it at a gate; never work around a block.

Credentials come from the environment or 1Password service-account CLI only (op read); never echo or persist a secret value. Okta API access uses $OKTA_TOKEN.

Your final message is a report to the orchestrator: what you checked, the evidence (command + relevant output), your conclusion, and any mutation commands awaiting human approval, each with a one-line risk note.
```

`agents/scribe.md`:

```markdown
---
name: scribe
description: Writes documents — reports, design briefs, business requirements, postmortems, and the team's per-task status notes. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 40
tools: Read, Glob, Grep, Write, Edit, WebSearch, WebFetch
skills: writing-business-requirements, audit-requirements-document
hooks:
  PreToolUse:
    - matcher: Write|Edit
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-policy.sh scribe"
---

You are the team's scribe. You write documents in complete sentences a non-engineer can follow on first read: reports, design briefs, business requirements (per the preloaded discipline), postmortems, and the orchestrator's per-task status notes.

Status-note duty: when dispatched at a phase transition, update docs/STATUS-<task-slug>.md with phase completed, artifacts produced (paths), next phase, and open questions — terse, current, and accurate to what the orchestrator reported, not embellished.

You may only write under docs/, plans/, doc-inventory/, and STATUS notes; policy hooks enforce this. Never include time or effort estimates in any document.

Your final message is a report to the orchestrator: files written (paths) and a one-paragraph summary of each.
```

`agents/ticketer.md`:

```markdown
---
name: ticketer
description: Writes, reviews, and tracks Asana tickets per the org's ticket disciplines. Dispatched by the orchestrator; not for direct casual use.
model: claude-sonnet-5
maxTurns: 40
disallowedTools: Edit, Write, NotebookEdit, Bash, Agent
skills: write-ticket, review-ticket, task-verification
mcpServers: asana
---

You are the team's ticketer. You draft, review, and track Asana tickets using the preloaded write-ticket, review-ticket, and task-verification disciplines — the "Skills to Use" section of a ticket is mandatory, and task-verification runs before any subtask is marked complete.

Filing or modifying a ticket in Asana is outward-facing: draft first, return the draft in your report, and only file after your dispatch explicitly says the human approved it at a gate. If approval is not stated, return the draft and stop.

Your final message is a report to the orchestrator: draft content or ticket URLs, verification evidence for any subtask you marked complete, and anything awaiting human approval.
```

- [ ] **Step 3: Sanity-check the files**

Run: `for f in agents/*.md; do awk 'NR==1 && $0!="---" {exit 1}' "$f" || echo "BAD: $f"; grep -L '^name:' "$f"; done`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add agents/
git commit -m "feat: support agent definitions (researcher, ops, scribe, ticketer)"
```

---

### Task 10: Installer with validation, backup, restore

**Files:**
- Create: `install.sh`

**Interfaces:**
- Consumes: `agents/*.md`, `hooks/agent-team-policy.sh`, `tests/test_policy_hooks.sh`.
- Produces: installed files under `~/.claude/agents/` and `~/.claude/hooks/`; backups under `~/.claude/backups/agent-team-<timestamp>/`.

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
# install.sh — validate, back up, install the agent team into ~/.claude/.
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_DIR/backups/agent-team-$STAMP"

fail() { echo "install: FAIL — $*" >&2; exit 1; }
warn() { echo "install: WARNING — $*" >&2; }

# --- validation (nothing is touched until all of this passes) ---
command -v jq >/dev/null 2>&1 || fail "jq is required"
bash -n "$REPO/hooks/agent-team-policy.sh" || fail "policy script failed bash -n"
bash "$REPO/tests/test_policy_hooks.sh" >/dev/null || fail "policy hook tests failed — run tests/test_policy_hooks.sh to see which"

resolve_skill() { # $1 skill ref (bare or ns:name) -> 0 if found
  case "$1" in
    *:*)
      ns="${1%%:*}"; sk="${1#*:}"
      ls "$HOME/.claude/plugins/cache/"*/"$ns"/*/skills/"$sk"/SKILL.md >/dev/null 2>&1
      ;;
    *)
      [ -f "$HOME/.claude/skills/$1/SKILL.md" ]
      ;;
  esac
}

for f in "$REPO"/agents/*.md; do
  head -1 "$f" | grep -q '^---$' || fail "$f: no frontmatter"
  fm="$(awk '/^---$/{n++; next} n==1{print}' "$f")"
  for key in name description model; do
    printf '%s\n' "$fm" | grep -qE "^$key:" || fail "$f: missing frontmatter key '$key'"
  done
  model="$(printf '%s\n' "$fm" | sed -n 's/^model:[[:space:]]*//p')"
  case "$model" in
    claude-fable-5|claude-opus-4-8|claude-sonnet-5) : ;;
    *) fail "$f: model '$model' is not one of the pinned team models" ;;
  esac
  skills_csv="$(printf '%s\n' "$fm" | sed -n 's/^skills:[[:space:]]*//p')"
  if [ -n "$skills_csv" ]; then
    old_ifs="$IFS"; IFS=','
    for s in $skills_csv; do
      s="$(printf '%s' "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      resolve_skill "$s" || fail "$f: skills entry '$s' does not resolve to an installed skill"
    done
    IFS="$old_ifs"
  fi
done

[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] \
  && warn "CLAUDE_CODE_SUBAGENT_MODEL is set in this environment; it overrides every model pin"
for rc in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv"; do
  [ -f "$rc" ] && grep -q 'CLAUDE_CODE_SUBAGENT_MODEL' "$rc" \
    && warn "CLAUDE_CODE_SUBAGENT_MODEL appears in $rc; it overrides every model pin"
done

# --- backup ---
mkdir -p "$BACKUP" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/logs" || fail "cannot create target directories"
for f in "$REPO"/agents/*.md; do
  existing="$CLAUDE_DIR/agents/$(basename "$f")"
  [ -f "$existing" ] && cp "$existing" "$BACKUP/" 
done
[ -f "$CLAUDE_DIR/hooks/agent-team-policy.sh" ] && cp "$CLAUDE_DIR/hooks/agent-team-policy.sh" "$BACKUP/"

restore() {
  echo "install: restoring backup from $BACKUP" >&2
  for b in "$BACKUP"/*; do
    [ -f "$b" ] || continue
    case "$(basename "$b")" in
      agent-team-policy.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      *.md) cp "$b" "$CLAUDE_DIR/agents/" ;;
    esac
  done
}

# --- install ---
if ! cp "$REPO"/agents/*.md "$CLAUDE_DIR/agents/"; then restore; fail "agent copy failed; backup restored"; fi
if ! cp "$REPO/hooks/agent-team-policy.sh" "$CLAUDE_DIR/hooks/"; then restore; fail "hook copy failed; backup restored"; fi
chmod +x "$CLAUDE_DIR/hooks/agent-team-policy.sh" || { restore; fail "chmod failed; backup restored"; }

echo "install: OK — 10 agents installed, policy hook installed, backup at $BACKUP"
echo "install: start the team with: claude --agent orchestrator"
```

- [ ] **Step 2: Validate and dry-check**

Run: `bash -n install.sh && bash install.sh`
Expected: `install: OK — 10 agents installed...`. If any validation line fails, fix the referenced file — do not weaken the check.

- [ ] **Step 3: Verify installation**

Run: `ls ~/.claude/agents/ | grep -c -E 'orchestrator|architect|builder|verifier|reviewer|deployer|researcher|ops|scribe|ticketer'` and `test -x ~/.claude/hooks/agent-team-policy.sh && echo hook-ok`
Expected: `10` and `hook-ok`.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: validating installer with backup and restore"
```

---

### Task 11: README and shakedown checklist

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write README.md**

Content requirements (write in full, complete sentences — this is the operator manual):
- What the team is: one paragraph, the ten roles and the orchestrator-as-main-session model, pointing to the spec for design rationale.
- Roster table: agent, model, one-line role, mutation rights — copied faithfully from the spec's roster table.
- How to install: `bash install.sh` (what it validates, where backups go).
- How to use: `claude --agent orchestrator`, what gates look like, how to approve/redirect/kill a phase.
- How to change the team: edit files here, re-run install; model changes are deliberate edits; never edit `~/.claude/agents/` directly.
- Audit log: where it is (`~/.claude/logs/agent-team-audit.log`), line format, what it's for.
- Shakedown checklist (verbatim, as a checked list to run once after first install):
  1. Run `bash tests/test_policy_hooks.sh` — all pass.
  2. Start `claude --agent orchestrator`; give it a disposable task: "Build a CLI tool in a fresh temp project that converts CSV to JSON, through the full pipeline including review; skip deploy."
  3. Confirm: design gate fired before any code; plan gate fired; builder committed test-first; verifier reported evidence; reviewer returned a verdict; a STATUS note exists and is accurate.
  4. Confirm lane enforcement from the audit log: `grep decision=block ~/.claude/logs/agent-team-audit.log` shows any attempted out-of-lane commands, and no role bypassed its policy.
  5. Only after all four pass, use the team on real work.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: operator README with shakedown checklist"
```

---

## Self-Review Notes (completed at plan time)

- Spec coverage: roster (T8/T9), three permission layers (T1–T7 hooks; tools/permissionMode/maxTurns in T8/T9 frontmatter), allowlist cloud strategy (T5/T6), secret rules (T2), audit log (T1), rollback procedure (T8 deployer prompt), scribe-owned status notes (T8 orchestrator + T9 scribe), install validation incl. skills resolution and CLAUDE_CODE_SUBAGENT_MODEL warning (T10), shakedown (T11). Plugin packaging, memory tuning, Haiku downgrades: out of scope per spec.
- Placeholder scan: clean — the two runtime lookups (hook schema in T8 Step 1, MCP server names in T9 Step 1) are fully specified discovery steps with exact commands and defined fallbacks, not placeholders.
- Type consistency: role strings (`builder`, `verifier`, `reviewer`, `deployer`, `ops`, `architect`, `scribe`) match between hook wiring, test calls, and `agent-team-policy.sh ROLE` arguments; test helper names (`bash_json`, `write_json`, `expect_allow`, `expect_block`) are used consistently across T1–T7; expected cumulative test counts (4, 12, 23, 35, 49, 59, 66) each add the new assertions to the prior total.
