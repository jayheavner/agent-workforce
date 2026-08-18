#!/usr/bin/env bash
# tests/test_agent_frontmatter.sh — static acceptance for the approve-intent
# trust model: no policy-hook references anywhere in agents/; every
# command-running agent carries bypassPermissions + audit + secrets; the
# doc-writing agents carry secrets; the executor's approval check exists.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HERE/../agents"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

[ -z "$(grep -rl 'agent-team-policy' "$AGENTS" 2>/dev/null)" ] && ok || no "no agent references agent-team-policy ($(grep -rl 'agent-team-policy' "$AGENTS" | tr '\n' ' '))"

COMMAND_RUNNERS="builder verifier reviewer ops deployer debugger executor test-author"
for a in $COMMAND_RUNNERS; do
  f="$AGENTS/$a.md"
  [ -f "$f" ] || { no "$a.md exists"; continue; }
  grep -q "permissionMode: bypassPermissions" "$f" && ok || no "$a carries permissionMode: bypassPermissions"
  grep -q "agent-team-audit.sh $a" "$f" && ok || no "$a registers the audit hook"
  grep -q "agent-team-secrets.sh $a" "$f" && ok || no "$a registers the secrets hook"
done

for a in architect scribe; do
  grep -q "agent-team-secrets.sh $a" "$AGENTS/$a.md" && ok || no "$a registers the secrets hook"
done

# The executor's zero-approval path is closed by the deployer-pattern check.
grep -qi "approval" "$AGENTS/executor.md" 2>/dev/null && ok || no "executor has the approval check"

# Authoring source or tests is builder work, closed at the tool layer rather
# than by a guard that can be reasoned past (2026-08-03: an executor hand-edited
# a source file and its test, then committed, opened, and merged the PR as a
# single actor — author, verifier, and integrator in one, with no independent
# review). The executor is a shell runner and carries no file-authoring tools.
EXEC_TOOLS="$(awk -F': *' '/^tools:/{print $2; exit}' "$AGENTS/executor.md")"
for t in Write Edit NotebookEdit; do
  printf '%s\n' "$EXEC_TOOLS" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -qx "$t" && no "executor must not carry the $t tool" || ok
done
grep -q "is builder work" "$AGENTS/executor.md" \
  && ok || no "executor names source/test authoring as builder work"

# The orchestrator can dispatch the executor, and the dispatch guard admits it.
grep -q "Agent(executor)" "$AGENTS/orchestrator.md" && ok || no "orchestrator tools include Agent(executor)"
grep -q "executor" "$HERE/../hooks/agent-team-dispatch-guard.sh" && ok || no "dispatch guard admits executor"

# workspace-isolation is enforced on every role that can write, and the guard's
# own POLICED_ROLES list is the set: a role in that list with no hook entry is
# policed by nobody, and the policy is prose again for it. The guard is wired on
# writing tools only (PreToolUse), never on Read, Glob or Grep — that reads are
# never gated is a property of this wiring, not of a sentence inside the guard.
POLICED_ROLES="builder test-author architect scribe executor deployer verifier reviewer debugger ops"
for a in $POLICED_ROLES; do
  f="$AGENTS/$a.md"
  [ -f "$f" ] || { no "$a.md exists"; continue; }
  grep -q "agent-team-worktree-guard.sh $a" "$f" \
    && ok || no "$a wires the worktree guard"
  awk -v role="$a" '/^  PreToolUse:/{p=1} /^  (PostToolUse|Stop|SubagentStop):/{p=0}
       p && index($0, "worktree-guard.sh " role){found=1} END{exit !found}' "$f" \
    && ok || no "$a wires the worktree guard as PreToolUse prevention"
  awk '/^  PreToolUse:/{p=1} /^  (PostToolUse|Stop|SubagentStop):/{p=0}
       p && /matcher:/ && (/Read/ || /Glob/ || /Grep/){bad=1} END{exit bad}' "$f" \
    && ok || no "$a does not gate reads (matcher names Read, Glob or Grep)"
done
# The Stop/SubagentStop backstop, for the roles whose work is a commit: a role
# that finishes outside a real workspace leaves evidence on the guard log rather
# than a silent success.
for a in builder test-author executor deployer; do
  awk -v role="$a" '/^  (Stop|SubagentStop):/{p=1} /^  (PreToolUse|PostToolUse):/{p=0}
       p && index($0, "worktree-guard.sh " role){found=1} END{exit !found}' "$AGENTS/$a.md" \
    && ok || no "$a wires the worktree guard as a Stop backstop"
done
# The guard's own list and this test's list are the same list.
for a in $POLICED_ROLES; do
  grep -q "POLICED_ROLES=.*$a" "$HERE/../hooks/agent-team-worktree-guard.sh" \
    && ok || no "the worktree guard's POLICED_ROLES names $a"
done
grep -q 'agent-team-worktree-guard.sh' "$HERE/../install.sh" \
  && ok || no "install.sh installs the worktree guard"

# Every other file-writing role is confined to the paths its role is for. These
# were prose in each agent's own instructions until 2026-08-03, and prose is what
# the incident routed around: the scribe refused correctly, and the work went to
# a role with no boundary at all.
for a in scribe architect test-author; do
  grep -q "agent-team-lane-guard.sh $a" "$AGENTS/$a.md" \
    && ok || no "$a wires the lane guard"
  awk '/^  PreToolUse:/{p=1} /^  (PostToolUse|Stop|SubagentStop):/{p=0} p && /lane-guard/{found=1} END{exit !found}' \
    "$AGENTS/$a.md" && ok || no "$a wires the lane guard as PreToolUse prevention"
done
grep -q 'agent-team-lane-guard.sh' "$HERE/../install.sh" \
  && ok || no "install.sh installs the lane guard"
# The builder is deliberately NOT lane-guarded: its confinement is its worktree,
# policed by the worktree guard, which also holds the acceptance-suite rule.
grep -q 'agent-team-lane-guard.sh' "$AGENTS/builder.md" \
  && no "builder must not wire the lane guard (its guard is the worktree guard)" || ok
# The executor carries no file-authoring tools, so it needs no write lane.
grep -q 'agent-team-lane-guard.sh' "$AGENTS/executor.md" \
  && no "executor must not need a lane guard (it has no file-authoring tools)" || ok

# The closeout hook is a single Stop-hook entrypoint (payload on stdin, no
# subcommands) wired in the orchestrator's frontmatter.
grep -qE '^  Stop:' "$AGENTS/orchestrator.md" \
  && ok || no "orchestrator frontmatter has a Stop hook section"
grep -q 'agent_team_closeout.py' "$AGENTS/orchestrator.md" \
  && ok || no "orchestrator wires the closeout Stop hook"
grep -qE 'agent_team_closeout\.py" (dispatch|subagent-stop|stop)' "$AGENTS/orchestrator.md" \
  && no "orchestrator still invokes retired closeout subcommands" || ok

# The stale escape hatch is gone: no agent tells the human to run commands.
grep -qi "faster from the human's own shell" "$AGENTS/orchestrator.md" && no "orchestrator still has the own-shell escape hatch" || ok

# Checks-and-balances (2026-07-26 spec): every specialist carries the
# WORKFORCE_REPORT marker contract, so the interrupt guard's missing-marker
# signal is meaningful for every role.
for a in architect builder debugger verifier reviewer deployer executor researcher ops scribe ticketer test-author; do
  grep -q "WORKFORCE_REPORT: $a" "$AGENTS/$a.md" && ok || no "$a carries the WORKFORCE_REPORT contract"
  grep -q 'agent-team-report-guard.sh' "$AGENTS/$a.md" && ok || no "$a wires the report guard Stop hook"
done

# Criteria-before-code: the orchestrator authors ACCEPTANCE CRITERIA, the
# builder treats them as the bar, and the guard enforces their presence.
grep -q "ACCEPTANCE CRITERIA" "$AGENTS/orchestrator.md" && ok || no "orchestrator authors ACCEPTANCE CRITERIA"
grep -q "ACCEPTANCE CRITERIA" "$AGENTS/builder.md" && ok || no "builder names the ACCEPTANCE CRITERIA contract"
grep -q "ACCEPTANCE CRITERIA" "$HERE/../hooks/agent-team-dispatch-guard.sh" && ok || no "dispatch guard enforces ACCEPTANCE CRITERIA"

# The orchestrator wires the interrupt guard on PostToolUse(Agent), and the
# plugin router runs it on its cost route.
grep -q 'agent-team-interrupt-guard.sh' "$AGENTS/orchestrator.md" && ok || no "orchestrator wires the interrupt guard"
grep -q 'agent-team-interrupt-guard.sh' "$HERE/../hooks/agent-team-plugin-router.sh" && ok || no "plugin router runs the interrupt guard"

# The skill mirror (skill-mode sessions run without hooks) carries the same
# contracts, and the Codex dispatcher enforces the report marker mechanically.
SKILL="$HERE/../skills/agent-workforce/SKILL.md"
ROLES="$HERE/../skills/agent-workforce/references/roles.md"
for needle in "WORKFORCE_REPORT" "ACCEPTANCE CRITERIA" "RESUME"; do
  grep -q "$needle" "$SKILL" && ok || no "SKILL.md carries $needle"
  grep -q "$needle" "$ROLES" && ok || no "roles.md carries $needle"
done
grep -q "WORKFORCE_REPORT" "$HERE/../bin/agent-workforce-dispatch" && ok || no "Codex dispatcher enforces WORKFORCE_REPORT"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
