---
name: closeout
description: Produce an evidence-backed completion ledger covering verification, review, documentation, memory, commits, deployment, integration, and cleanup without silently mutating Git or personal memory.
---

# Closeout

Use this skill when work is being finished, shipped, wrapped up, handed off, or
reported complete. It complements `finishing-a-branch`: this skill defines the
ledger and evidence contract; `finishing-a-branch` governs branch integration
and cleanup decisions.

## Completion is not a ledger heading

Agree the delivery target before closeout: an artifact, an integrated code
change, or a deployed service. The target makes the required ledger fields
explicit — for example, an integrated code change needs fresh verification,
review, commit, and integration; a deployed service also needs deployment and
post-deploy evidence.

The ledger reports state; it does not create completion. Call work `done`,
`complete`, or `shippable` only when every field required by the delivery target
is `pass` after the final edit. If a required field is `pending`, `fail`, or
`UNCHECKED`, report `NOT SHIPPABLE`, name the exact next action, and use a
precise interim state such as `implemented and locally verified`. `not
applicable` is valid only when the agreed delivery target genuinely excludes the
field; it cannot hide an unapproved deploy, integration, or release check.

## Required ledger

Write one ledger in the task status note and repeat its material contents in the
final response. Include these fields in this order:

1. `verification`
2. `review`
3. `documentation`
4. `memory`
5. `commit`
6. `deployment`
7. `integration`
8. `cleanup`

Each value is exactly one of `pass`, `fail`, `pending`, or `not applicable`,
followed by evidence or the next action. A report from another agent is not
enough: read the relevant command output, diff, artifact, or approval.

## Evidence rules

- Verification is fresh and criterion-specific after the final code edit.
  Record the exact command and the relevant output; use `UNCHECKED` when an
  obstacle prevents the check. A focused test may establish an acceptance
  criterion, but the required full suite establishes shipment readiness.
- Review covers the full relevant diff and security-sensitive context.
- Documentation names the status note, plan/spec, decision record, or other
  artifact written. Do not invent a changelog or release note that was not
  requested.
- Commit names the exact hash and message, or says why no commit was authorized
  or possible. Never stage unrelated dirty files.
- Deployment names the approval, known-good identifier, deployment result,
  smoke evidence, and rollback result. A local-only task is `not applicable`.
- Integration names the selected human path: merged, PR/opened, held, or
  explicitly discarded. Do not infer integration from a successful test.

## Finalizer ownership

For repository changes, the executor finalizer owns the transition from green
evidence to a clean local delivery. The implementation request authorizes a
focused local commit unless the human explicitly opted out. Stage only this
task's delta, include its plan/status/handoff artifacts, follow the repository's
commit convention, and record the hash. Do not push without separate authority
and do not absorb baseline dirt.

## Memory state

Use one of these exact states:

- `not requested`
- `not reusable`
- `recorded: docs/memory/<file>.md`
- `pending human approval: docs/memory/<proposed-file>.md`

Project-memory records follow `docs/memory/README.md`. Never claim that a
personal Codex memory store, profile memory, or session memory was updated
unless the active surface provides that operation and the operation actually
ran. Never put secrets in a memory record.

## Git cleanup audit

When a shell is available, run the read-only audit before proposing cleanup:

```bash
bin/agent-workforce-closeout --repo <checkout> --base <base> --format text
```

Cleanup requires all of these conditions: integration is confirmed; the target
branch or worktree is merged into the selected base; it is clean; it is not the
current checkout; and the task created it. When integration and cleanup are
inside standing authorization, the finalizer removes eligible targets without a
ceremonial confirmation; an explicit hold wins. Otherwise ask once for the
missing authority. Do not delete by age, use force cleanup for convenience, or
remove a branch/worktree owned by another task.

If the audit cannot run, mark cleanup `UNCHECKED` and identify the obstacle.
