---
name: verifying
description: Evidence before claims — check each stated acceptance criterion by running the exact command and reading its real output; per-criterion verdicts pass/fail/UNCHECKED with evidence attached, never averaged. Use when about to claim work is complete, fixed, or passing against enumerable criteria — closing a ticket, finishing a plan task, reporting results against a spec. Not for exercising an app end-to-end to watch a change work (that is the client verify skill's job); verifying is the criterion-by-criterion verdict table behind any completion claim.
---

# Verifying

Job: establish what is actually true before anything is reported done, fixed, or
passing. A claim without fresh command output behind it is a guess, not a
verification.

## The discipline

For each criterion to verify:

1. Identify the one command whose output can prove or disprove it — as close to
   the user-visible behavior as the environment allows.
2. Run it. Read the full output, not just the exit code — a suite can exit 0
   having skipped everything, and a build can "succeed" while logging the error
   you were checking for.
3. Record together: the criterion, the exact command, the relevant output
   verbatim, and the verdict.

Rerun after the last change, not before it — evidence gathered earlier in the
session is stale the moment anything was edited.

## Verdicts

- **pass** — the output shows the criterion holding. Quote the line that shows it.
- **fail** — the output shows it not holding. Include the output verbatim, never
  paraphrased; the reader debugs from your evidence.
- **UNCHECKED** — you could not run a check. State why, with the evidence of the
  obstacle itself (missing file, absent tool, no credentials). Never silently skip.

One failing criterion means the overall verdict is fail. Verdicts don't average.

## Claim → proof

| Claim | Proof (not this) |
|---|---|
| Bug fixed | Test of the original symptom passes (not "code changed") |
| Agent/subagent completed X | VCS diff shows the changes (not the agent's report) |
| Tests pass | The suite ran fresh, full output read (not a cached/partial run) |
| Requirements met | Line-by-line checklist against the requirements (not "tests pass") |
| Regression-tested | Red-green proof: pass → revert fix → MUST fail → restore → pass |

## Traps

- **Partial greens:** "tests pass" when only a subset ran. Record which suite and
  how many tests the output reports.
- **Proxy evidence:** the file existing doesn't mean it works; compiling doesn't
  mean it's correct; the server starting doesn't mean the endpoint answers.
- **Wishful reading:** searching output for the success line and stopping.
  Search for the failure lines too.
