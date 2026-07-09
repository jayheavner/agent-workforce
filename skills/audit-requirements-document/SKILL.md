---
name: audit-requirements-document
description: Audit a business-requirements document for standards violations (implementation detail, technology specifics, architecture rationale, or test procedures that belong elsewhere) and produce a violation report with recommended destinations for the misplaced content.
---

# Audit Requirements Document

## Overview

This skill audits a business-requirements document to detect violations of the standards defined in the `writing-business-requirements` skill, then reports each violation together with the destination where the misplaced content belongs (for example `.claude/rules/`, `docs/decisions/DECISIONS.md`, `docs/setup/`, or `tests/`).

You perform this audit directly. You read the target document, apply the pattern catalog in `patterns.md` by hand, and write a report. There is no automated pipeline and no code to run: the judgment is yours, and the report records which pattern categories you applied so a human can spot-check your work.

**Purpose:** Maintain a clean separation between business requirements (WHAT the system does) and everything else: implementation details (HOW it is built), technology choices, architecture rationale, and test procedures.

## When to Use

**Primary triggers:**
- After authoring a new requirements document (pairs with `writing-business-requirements`).
- Before code review of a requirements change.
- During a requirements refactoring effort.
- When onboarding a team member to the requirements standards.
- During a periodic documentation audit.

**Indicators that an audit is needed:**
- Requirements contain implementation language ("try/except", "call the API", "return a dictionary").
- Requirements name specific libraries or frameworks.
- Requirements include test procedures or coverage metrics.
- Requirements explain architecture decisions or technology choices.
- Content mixes concerns and breaks the WHAT/HOW separation.

**Do NOT use this skill for:**
- General document editing (use ordinary editing tools).
- Code review (use the `code-review` skill).
- Authoring requirements from scratch (use `writing-business-requirements` first).

## How to Perform the Audit

Work through these four steps in order. Keep notes as you go; the notes become the report.

### Step 1: Read the target document in full

Read the requirements document end to end before judging any single line. Note the section headings and the line ranges so you can cite precise locations in the report. Requirement identifiers (for example FR-003) matter; preserve them exactly when you quote a section.

### Step 2: Apply the pattern catalog directly

Open `patterns.md` (in this skill's directory) and walk each requirement against every pattern category:

- **Implementation Details**: return values and types, exception handling, function/API calls, data structures, control flow, technical implementation terms, and unverified performance claims.
- **Technology Specifics**: library and framework names, API endpoints and URLs, configuration values, and file paths.
- **Architecture Rationale**: design decisions and tradeoffs, system design patterns, and technology comparisons.
- **Test Plans and Procedures**: test cases and scenarios, coverage requirements, verification methods, and assertions.

Apply the catalog's false-positive rules: implementation language is allowed inside fenced code blocks, in clearly-labelled examples, in attributed quotes, and in cross-references that merely point elsewhere. Flag content only when it states HOW the system works inside a requirement statement or its rationale.

For each match, record the requirement identifier or heading, the line range, the offending text, the pattern category it triggered, and a suggested plain-requirements rewrite.

### Step 3: Assign a destination for each violation

Use the destination mapping in `patterns.md` to decide where each piece of misplaced content belongs. In summary:

- Implementation detail and coding-standard content goes to `.claude/rules/`.
- Technology choices, design patterns, and tradeoffs go to `docs/decisions/DECISIONS.md`.
- Library setup, API authentication, and configuration guidance go to `docs/setup/` or the appropriate `config/` file.
- File-organization conventions go to project guidance.
- Test cases, coverage rules, and verification methods go to `tests/` or the testing rules file.

The destination is a recommendation for the human, not an action you take. This skill does not move or rewrite content; it reports.

### Step 4: Write the violation report

Produce a single Markdown report with the structure shown below. The report must list the pattern categories you applied so a human can confirm the audit was complete, then list each violation with its location, category, severity, and recommended destination.

## Report Template

```markdown
# Requirements Audit Report

**Document audited:** docs/requirements/behavioral/classification_workflow.md
**Sections reviewed:** 1-145
**Requirement identifiers preserved:** yes

## Pattern categories applied
- Implementation Details: applied
- Technology Specifics: applied
- Architecture Rationale: applied
- Test Plans and Procedures: applied

## Violations

### Violation 1
- Location: FR-003 (lines 50-57)
- Category: implementation_detail (exception handling)
- Severity: HIGH
- Found: "The classifier shall catch exceptions using try/except blocks and return None when classification fails."
- Why: names an implementation construct and a return value; describes HOW, not WHAT.
- Recommended destination: .claude/rules/python-style.md (exception handling section)
- Suggested requirement rewrite: "When document classification fails, the system shall display an error to reviewers and continue processing the remaining documents."

### Violation 2
- Location: FR-009 (lines 204-211)
- Category: test_procedure
- Severity: HIGH
- Found: "Assert unit test coverage reaches 90%; run integration test with real API calls."
- Why: describes test implementation and coverage, not a business outcome.
- Recommended destination: tests/README.md (test plan) and .claude/rules/testing.md (coverage policy)
- Suggested acceptance-criteria rewrite: "Given two submissions from the same organization on different dates, when the newer submission loads, the organization record reflects only the newer data."

## Summary
- Total violations: 2
- By severity: HIGH 2, MEDIUM 0, LOW 0
- By category: implementation_detail 1, test_procedure 1
```

Severity follows `patterns.md`: HIGH for implementation language inside a requirement statement, MEDIUM for useful information sitting in the wrong document (for example architecture rationale), LOW for a minor clarity issue or a missing cross-reference.

## Worked Examples

### Example 1: Implementation detail in a requirement

Original (lines 50-57):

```markdown
### FR-003: Error Handling
The classifier shall catch exceptions using try/except blocks and return None
when classification fails, allowing the calling code to handle errors gracefully.
```

Category: implementation_detail. It names a construct ("try/except"), a return value ("return None"), and code-level behavior ("calling code"). Recommended destination: `.claude/rules/python-style.md`. Requirement rewrite:

```markdown
### FR-003: Classification Error Handling
When document classification fails, the system shall display error messages to
reviewers and continue processing the remaining documents.
```

### Example 2: Test procedure in a requirement

Original (lines 204-211):

```markdown
### FR-009: Duplicate Organization Handling
**Acceptance Criteria:**
- Assert unit test coverage reaches 90%
- Run integration test with real API calls
```

Category: test_procedure. It states a testing approach rather than a business outcome. Recommended destination: `tests/README.md` and `.claude/rules/testing.md`. Acceptance-criteria rewrite:

```markdown
**Acceptance Criteria:**
- Given two submissions from the same organization submitted on different dates,
  when the system loads the newer submission, then the organization record
  reflects data from the newer submission only.
```

### Example 3: Architecture rationale in a requirement

Original (lines 29-42):

```markdown
### FR-005: Multi-Model Consensus
The system shall use one model as primary and a second as secondary because
single-model accuracy was insufficient; dual-model consensus reached a higher
accuracy in our evaluation dataset, at an acceptable combined cost.
```

Category: architecture_rationale. It explains a technology choice and a cost-performance tradeoff ("why we built it this way"). Recommended destination: `docs/decisions/DECISIONS.md`. Requirement rewrite:

```markdown
### FR-005: Classification Accuracy Validation
The system shall classify documents at or above the agreed accuracy target,
verified against a manually labelled test dataset.
```

The extracted rationale becomes a decision record (context, options evaluated, decision, rationale, consequences) in `docs/decisions/DECISIONS.md`.

## Integration with writing-business-requirements

This skill enforces the standards that `writing-business-requirements` defines.

**Workflow:**
1. Author requirements with `writing-business-requirements`.
2. Audit them with this skill.
3. Review the reported violations and confirm each recommended destination.
4. Apply the rewrites and relocate the extracted content, then commit.

See also: `~/.claude/skills/writing-business-requirements/SKILL.md`.

## References

- Pattern catalog: `patterns.md` (this skill's directory): the violation categories, detection cues, false-positive rules, and destination mapping you apply.
- Related skills: `writing-business-requirements` (defines the standards), `code-review` (code-level review, not requirements), `task-verification` (pre-completion verification).
- Standards references: BABOK v3 (IIBA), IEEE 830, ISO/IEC/IEEE 29148:2018.

## Limitations

- The audit is a human-performed judgment; a reviewer should confirm the findings before content is relocated.
- Destination mapping may need adjustment for edge cases.
- Pattern cues can miss context-dependent violations and cannot catch semantic problems that need domain knowledge.
- Vague or ambiguous requirements without implementation keywords are found by human reading, not by the catalog.

## Success Criteria

The audit is done well when:
- Every pattern category in `patterns.md` was applied and the report says so.
- Each violation cites a precise location, a category, a severity, and a recommended destination.
- Suggested rewrites state WHAT the system does, free of implementation language.
- Requirement identifiers and document structure are cited accurately.
