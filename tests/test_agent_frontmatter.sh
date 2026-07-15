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

COMMAND_RUNNERS="builder verifier reviewer ops deployer debugger executor"
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

# The orchestrator can dispatch the executor, and the dispatch guard admits it.
grep -q "Agent(executor)" "$AGENTS/orchestrator.md" && ok || no "orchestrator tools include Agent(executor)"
grep -q "executor" "$HERE/../hooks/agent-team-dispatch-guard.sh" && ok || no "dispatch guard admits executor"

# The stale escape hatch is gone: no agent tells the human to run commands.
grep -qi "faster from the human's own shell" "$AGENTS/orchestrator.md" && no "orchestrator still has the own-shell escape hatch" || ok

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
