# Parent / subtask templates

Defaults used when `policy:ticket-format` names no override.

## Parent task

```markdown
## Objective
[What business outcome are we achieving?]

## Context
[Why is this needed? What problem does it solve?]

## Success Criteria
- [ ] [Observable outcome 1 - must be verifiable]
- [ ] [Observable outcome 2 - must be verifiable]

## References
- Requirements: [link, file path, or memory ID]
- Decisions: [reference]
- Related tasks: [reference]

## Notes
[Constraints or considerations that affect every subtask]
```

Success criteria here describe outcomes, not steps — no "first do X, then Y".
The parent has no "Skills to Use" section; that's a subtask concern.

## Subtask

```markdown
**Context:** Read the parent task first — it has the objective and any
constraints that apply across all subtasks.

## Task
[Specific action to take - be precise]

## Acceptance Criteria
- [ ] [Verifiable outcome 1]
- [ ] [Verifiable outcome 2]

## Verification
[Exact command(s), file checks, or validation steps used to confirm each
criterion. Unit tests only — no criterion may depend on an integration test.]

## Context
[Links to docs, code files, or related tasks needed to do the work without
hunting for it mid-task]

## Skills to Use
[Specific skill names required for this task type, from
`task-type-map.md`, with one line on why each applies]
```

## Draft-review format

Show this before creating anything in Asana:

```markdown
## Proposed Ticket Structure

**Parent Task:** [Name]
- Objective: [what we're achieving]
- Success criteria: [how we know it's done]

**Subtasks:**
1. [name] — Acceptance: [criteria] — BLOCKS -> 2, 3
2. [name] — Acceptance: [criteria] — BLOCKED BY -> 1
3. [name] — Acceptance: [criteria] — BLOCKED BY -> 1
```
