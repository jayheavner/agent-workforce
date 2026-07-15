# Requirement templates

Defaults used when no project convention overrides them (see SKILL.md,
"Identifiers, priority, and citations" — craft convention, not policy).

## Business context (document level — write once)

```markdown
## Business Context

**Stakeholders:**
- [Role] ([what they do with the system])

**Business Domain:**
[1-3 sentences: who does what, with what, and why it matters to the business]

**Business Objectives:**
- [Measurable business outcome this document's requirements serve]
```

## Functional requirement (FR-n)

```markdown
### FR-[n]: [Capability Name]

**Priority:** Must Have | Should Have | Could Have | Won't Have
**Source:** [Stakeholder or business driver]
**Status:** Proposed | Approved | Implemented | Verified

**Requirement:**
[Actor] shall [verb] [object] [conditions], stated as observable behavior.

**Rationale:**
[1-2 sentences: why users need this, tied to a business objective]

**Dependencies:** [FR-001, FR-003] | None

**Acceptance Criteria:** (minimum 2-3)
- Given [precondition], When [action/trigger], Then [observable outcome]
- Given [precondition], When [action/trigger], Then [observable outcome]

**Verification Method:** Inspection | Test | Analysis | Demonstration
```

## Priority (MoSCoW)

- **Must Have** — critical, non-negotiable.
- **Should Have** — important, system can function without it.
- **Could Have** — desirable if time/budget permits.
- **Won't Have** — out of scope for this release.

## Status

Proposed (under review) -> Approved (accepted) -> Implemented (built, not
yet verified) -> Verified (tested and confirmed).

## Verification methods

- **Inspection** — review of design docs, code, or interface. Use for UI
  layout, data formats, documentation.
- **Test** — execute the system with test cases. Use for functional
  behavior, error handling, data processing.
- **Analysis** — mathematical proof or simulation. Use for algorithms,
  performance, capacity.
- **Demonstration** — operate the system for stakeholders. Use for user
  workflows, end-to-end scenarios.
