# Report templates

Defaults used when `policy:ticket-format` names no override.

## Ticket presentation

```markdown
# Ticket: [Title]
Link: [Asana URL]

**Status:** [Current state]
**Assignee:** [Person or unassigned]
**Parent:** [Parent link and title] (if applicable)

## Summary
[Ticket description]

## Subtasks
- [ ] Subtask 1
- [x] Subtask 2 (completed)

## Dependencies
**Blocked by:** [links + titles]
**Blocking:** [links + titles]
```

## Due-diligence findings

```markdown
## Due Diligence

### Ownership
PASS - Unassigned or assigned to this session
STOP - Assigned to [name] - do not proceed without explicit takeover

### Validity
PASS - Valid, work still needed
WARNING - Questionable - [specific concern]
FAIL - Invalid - [already done / duplicate / outdated]

### Blockers
None found / [list]

### Scope Analysis
**As written:** [ticket summary]
**Actual scope discovered:** [what implementation really requires]
**Components affected:** [systems/files/infra that will change]
**Hidden dependencies:** [infra, service, schema, config]

**Separation of concerns:**
PASS - Single concern, well-scoped
WARNING - Multiple concerns mixed - [describe]
FAIL - Should be split - [why]

**Decomposition recommendation (if any):**
1. [Ticket 1] - [what it covers] (BLOCKS -> 2)
2. [Ticket 2] - [what it covers] (BLOCKED BY -> 1)

### Required Skills
[For each skill named in "Skills to Use":]
- **skill-name** - resolves: yes/no - [reason it's required]
[If a name doesn't resolve, say so explicitly - it blocks proceeding.]

### Recommended Next Step
[One of: Proceed / Split ticket first / Clarify requirements / Resolve
blockers first / Close or update ticket]
```
