#!/usr/bin/env bash
# Verify process assurance is wired into both workforce surfaces and installation.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

has() { # file, fixed text, label
  if grep -qF -- "$2" "$ROOT/$1"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$3"
  fi
}

has agents/orchestrator.md 'agent-team-process-assurance.py" dispatch' \
  'snapshot orchestrator lacks assurance dispatch hook'
has agents/orchestrator.md 'agent-team-process-assurance.py" subagent-stop' \
  'snapshot orchestrator lacks assurance result recorder'
has agents/orchestrator.md 'agent-team-process-assurance.py" stop' \
  'snapshot orchestrator lacks assurance closeout hook'
has agents/reviewer.md '## Process-audit mode' 'reviewer lacks process-audit port'
has agents/reviewer.md 'WORKFORCE_PROCESS_AUDIT_RESULT:' 'reviewer lacks strict result marker'
has agents/reviewer.md '`VIOLATED`' 'reviewer cannot express a checklist violation'
has agents/orchestrator.md 'WORKFORCE_CHARTER:' 'orchestrator lacks charter protocol'
has agents/orchestrator.md 'WORKFORCE_PROCESS_AUDIT_REQUEST:' 'orchestrator lacks audit request protocol'
has agents/orchestrator.md 'WORKFORCE_TRANSITION:' 'orchestrator lacks transition protocol'
has skills/agent-workforce/SKILL.md 'process-audit mode' 'Codex workforce lacks audit schedule'
has skills/process-auditing/SKILL.md 'Job:' 'process-auditing skill is missing'
has hooks/agent-team-plugin-router.sh 'assurance-dispatch' 'plugin router lacks assurance dispatch route'
has hooks/agent-team-plugin-router.sh 'assurance-subagent' 'plugin router lacks assurance result route'
has hooks/agent-team-plugin-router.sh 'assurance-stop' 'plugin router lacks assurance closeout route'
has hooks/hooks.json 'assurance-dispatch' 'plugin hook registry lacks assurance dispatch'
has hooks/hooks.json 'assurance-subagent' 'plugin hook registry lacks assurance recorder'
has hooks/hooks.json 'assurance-stop' 'plugin hook registry lacks assurance closeout'
has install.sh 'process_assurance.py' 'Claude installer omits assurance engine'
has install.sh 'agent-team-process-assurance.py' 'Claude installer omits assurance adapter'
has install.sh 'test_process_assurance_hook.sh' 'Claude installer omits assurance regression'
has install-codex.sh 'process_assurance.py' 'Codex installer omits assurance engine'
has bin/agent-workforce-dispatch '--assurance-session' 'Codex wrapper lacks assurance session support'
has bin/agent-workforce-dispatch 'WORKFORCE_PROCESS_AUDIT_RESULT:' 'Codex wrapper lacks result capture'
has install.sh 'test_process_assurance_cli.sh' 'Claude installer omits assurance CLI regression'
has bin/agent-workforce-process-assurance 'effectiveness-record' 'operator CLI lacks effectiveness evidence recording'

python3 "$ROOT/scripts/render_codex_agents.py" --check >/dev/null 2>&1 \
  && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); printf 'FAIL: generated Codex agents are stale\n'; }

printf 'process-assurance integration tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
