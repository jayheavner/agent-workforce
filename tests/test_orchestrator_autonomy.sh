#!/usr/bin/env bash
# tests/test_orchestrator_autonomy.sh — protects the orchestrator from
# bouncing runnable commands or already-settled decisions back to the human.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SKILL="$ROOT/skills/agent-workforce/SKILL.md"
ROLES="$ROOT/skills/agent-workforce/references/roles.md"
PASS=0
FAIL=0

expect_grep() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$ROOT/agents/orchestrator.md"; then
    PASS=$((PASS + 1)); echo "PASS: $2"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — not found: $1"
  fi
}

expect_absent() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$ROOT/agents/orchestrator.md"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — forbidden text present: $1"
  else
    PASS=$((PASS + 1)); echo "PASS: $2"
  fi
}

expect_skill_grep() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$SKILL"; then
    PASS=$((PASS + 1)); echo "PASS: $2"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — not found in skill: $1"
  fi
}

expect_skill_absent() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$SKILL"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — forbidden skill text present: $1"
  else
    PASS=$((PASS + 1)); echo "PASS: $2"
  fi
}

expect_roles_grep() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$ROLES"; then
    PASS=$((PASS + 1)); echo "PASS: $2"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — not found in roles: $1"
  fi
}

expect_roles_absent() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$ROLES"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — forbidden roles text present: $1"
  else
    PASS=$((PASS + 1)); echo "PASS: $2"
  fi
}

expect_file_grep() { # $1 file, $2 fixed text, $3 label
  if grep -qF -- "$2" "$1"; then
    PASS=$((PASS + 1)); echo "PASS: $3"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $3 — not found in $1: $2"
  fi
}

expect_file_absent() { # $1 file, $2 fixed text, $3 label
  if grep -qF -- "$2" "$1"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $3 — forbidden text present in $1: $2"
  else
    PASS=$((PASS + 1)); echo "PASS: $3"
  fi
}

expect_absent "if the action is faster from the human's own shell" \
  "trivial work has no human-shell delegation loophole"
expect_grep "never hand the human a command to run" \
  "runnable commands stay with the workforce"
expect_grep 'arbitrary shell work goes to the **executor**' \
  "unowned commands have an explicit specialist route"
expect_grep "dispatch the executor or domain specialist to start it and keep the session open" \
  "interactive commands start inside a specialist dispatch"
expect_grep "Ask only for the irreducible human action" \
  "interactive assistance is limited to the human-only step"
expect_grep "check it against the original request, the findings ledger, approved artifacts, and specialist evidence" \
  "questions are screened against already-established intent and evidence"
expect_grep "The user's stated outcome is settled intent, not an open preference" \
  "the orchestrator does not ask the user to repeat the requested behavior"
expect_grep "cause, regression proof, and restoration of affected in-scope work" \
  "confirmed incidents carry their necessary remediation scope"
expect_grep "asks permission to execute the settled remedy" \
  "authority gates do not reopen settled scope or behavior"
expect_grep "A direct request or explicit choice consumes the applicable gate" \
  "explicit user authorization is consumed exactly once"
expect_grep '"Deploy main now, then redrive the DLQ"' \
  "deploy-now choice is specified as deploy authorization"
expect_grep "do not ask again" \
  "orchestrator cannot add a ceremonial second approval"
expect_absent "The deploy gate is always explicit" \
  "deploys already authorized by the user do not force another gate"
expect_grep "The default is uninterrupted execution" \
  "orchestration defaults to unattended progress"
expect_grep "The original request is standing authorization" \
  "the initial request authorizes ordinary in-scope work"
expect_grep "Pause only when" \
  "human interruption is limited to enumerated exceptions"
expect_absent "→ GATE →" \
  "software routes do not stop at routine phase boundaries"
expect_absent "→ final gate" \
  "completed small work is reported instead of awaiting ceremonial approval"
expect_absent "GATE before anything outward-facing" \
  "explicitly requested outward work does not force a redundant gate"
expect_skill_grep "default is uninterrupted execution" \
  "Codex workforce also defaults to unattended progress"
expect_skill_grep "consumes that authorization exactly once" \
  "Codex workforce consumes explicit approval once"
expect_skill_absent "Architect combined spec and plan -> gate" \
  "Codex small route has no automatic artifact gate"
expect_skill_absent "Always require explicit approval before" \
  "Codex skill does not discard standing authorization"
expect_roles_grep "states the authorization source" \
  "deployer accepts authorization from the original request or choice"
expect_roles_grep "not a fresh approval" \
  "operations role does not manufacture another gate"
expect_roles_absent "human approved the deploy gate" \
  "deployer does not require a ceremonial gate label"
expect_roles_absent "act only after explicit approval" \
  "ticket writes can use standing authorization"
expect_grep "Do not narrate either lookup" \
  "build detection runs silently before status is reported"
expect_grep "Only after both reads fail" \
  "unverified build is reported only after both sources fail"
expect_grep "The first visible prose must be the one final build line" \
  "startup emits one resolved build status without contradiction"
expect_absent "At the final gate" \
  "closeout is not an automatic approval stop"
expect_absent "at gates and at task completion" \
  "status notes do not depend on routine gates"
expect_absent "present the exact cleanup commands and wait for the human's decision" \
  "authorized cleanup is executed instead of handed back for approval"
expect_absent "A gate with no open decision" \
  "artifact completion cannot manufacture an approval question"
expect_absent "no gate unless the action itself is outward-facing or irreversible" \
  "trivial outward work honors standing authorization"
expect_absent "how many phases and gates" \
  "tier selection no longer counts routine gates"
expect_file_grep "$ROOT/agents/deployer.md" "states the authorization source and scope" \
  "Claude deployer accepts standing authorization"
expect_file_absent "$ROOT/agents/deployer.md" "explicit human deploy-gate approval" \
  "Claude deployer does not demand a gate label"
expect_file_grep "$ROOT/agents/executor.md" "original request as standing authorization" \
  "Claude executor accepts the original request"
expect_file_absent "$ROOT/agents/ops.md" "gate-approved scope" \
  "Claude ops does not demand gate-approved wording"
expect_file_absent "$ROOT/agents/ticketer.md" "human approved it at a gate" \
  "Claude ticketer accepts authorized outward writes"
expect_file_absent "$ROOT/codex/model-policy.json" "Run a single obvious approved command" \
  "Codex fast executor description uses authorization language"
expect_file_absent "$ROOT/codex/model-policy.json" "under an approved goal" \
  "Codex deep executor description uses authorization language"
expect_file_absent "$ROOT/codex/model-policy.json" "explicitly approved deployment" \
  "Codex deployer description does not imply a second approval"
expect_file_absent "$ROOT/codex/model-policy.json" "explicit write gates" \
  "Codex ticketer description does not advertise routine gates"

if grep -qF -- 'test_orchestrator_autonomy.sh' "$ROOT/install.sh"; then
  PASS=$((PASS + 1)); echo "PASS: installer runs the autonomy regression"
else
  FAIL=$((FAIL + 1)); echo "FAIL: installer runs the autonomy regression — test not found in install.sh"
fi

printf 'orchestrator-autonomy tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
