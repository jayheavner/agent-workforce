---
name: writing-business-requirements
description: Use when writing or reviewing business requirements documents following industry standards (BABOK v3, IEEE 830)
---

# Writing Business Requirements

## Overview

Business requirements describe WHAT capabilities users need to accomplish their work, not HOW the system implements those capabilities.

**Industry Standards:** This skill follows BABOK v3 (Business Analysis Body of Knowledge) and IEEE 830 (Software Requirements Specification) standards for requirements documentation.

**Core principle:** Each requirement must be atomic, testable, unambiguous, and traceable. Requirements describe observable system behavior, not internal implementation.

## When to Use

Use this skill when:
- Writing new business requirements
- Reviewing existing requirements for compliance with standards
- Fixing requirements defects identified in audits
- Extracting business needs from mixed documentation

**Post-Authoring Workflow:**
After completing requirements documentation, invoke the `audit-requirements-document` skill to detect violations and extract misplaced content to appropriate destinations. This ensures requirements remain focused on business capabilities (WHAT) without implementation details (HOW).

## Document Structure

Business requirements documents follow this hierarchy:

### 1. Business Context (DOCUMENT LEVEL - WRITE ONCE)

Appears at the top of the document, not in individual requirements:

```markdown
## Business Context

**Stakeholders:**
- Grant reviewers (evaluate nonprofit applications)
- System administrators (maintain classification system)
- Nonprofit applicants (submit supporting documents)

**Business Domain:**
Grant reviewers evaluate applications from nonprofit organizations applying for funding.
Each application includes eligibility documents (Form 990, IRS determination letters,
financial statements) that prove the organization's 501(c)(3) tax-exempt status.

**Business Objectives:**
- Reduce manual document review time by 60%
- Ensure 100% of applications receive eligibility determination
- Maintain audit trail of classification decisions
```

### 2. Functional Requirements

Each functional requirement follows this format:

```markdown
### FR-[ID]: [Capability Name]

**Priority:** Must Have | Should Have | Could Have | Won't Have
**Source:** [Stakeholder or business driver]
**Status:** Proposed | Approved | Implemented | Verified

**Requirement:**
[The system/user] shall [verb] [object] [qualifier under specific conditions].

**Rationale:**
[Why this capability is needed - business justification in 1-2 sentences]

**Dependencies:**
[Related requirements: FR-001, FR-003] | None

**Acceptance Criteria:**
- Given [precondition], When [action/trigger], Then [observable outcome]
- Given [precondition], When [action/trigger], Then [observable outcome]
- Given [precondition], When [action/trigger], Then [observable outcome]
```

## Requirement Attributes (Mandatory)

Every functional requirement MUST include:

### Unique Identifier
- Format: `FR-[number]` (e.g., FR-001, FR-012, FR-143)
- Sequential numbering within document
- Enables traceability from requirements → design → tests → code

### Priority (MoSCoW Method)
- **Must Have:** Critical for system to function, non-negotiable
- **Should Have:** Important but system can function without it
- **Could Have:** Desirable if time/budget permits
- **Won't Have:** Out of scope for this release

### Source
- Who requested this capability (stakeholder name or role)
- OR business driver (regulatory compliance, cost reduction, user satisfaction)

### Status
- **Proposed:** Under review, not yet approved
- **Approved:** Accepted for implementation
- **Implemented:** Code written, not yet verified
- **Verified:** Tested and confirmed working

### Requirement Statement
- **SHALL** language for mandatory behavior
- **SHOULD** language for recommended behavior
- **MAY** language for optional behavior

Format: `[Actor] shall [verb] [object] [conditions]`

Examples:
- "The system shall display error messages when document classification fails"
- "Grant reviewers shall receive notifications when batch processing completes"
- "The system shall continue processing remaining documents when individual documents fail"

### Rationale
- 1-2 sentence business justification
- Answers: "Why do users need this capability?"
- Links requirement to business objectives

### Dependencies
- Related requirements that must be implemented first
- Format: FR-001, FR-003, FR-007 OR "None"
- Enables proper sequencing of development work

### Acceptance Criteria (Given-When-Then)
- **Given:** Precondition or system state before action
- **When:** Action taken or event triggered
- **Then:** Observable outcome that can be verified

Minimum 2-3 acceptance criteria per requirement. Each criterion must be:
- **Testable:** Can be verified through inspection, test, analysis, or demonstration
- **Unambiguous:** Only one interpretation possible
- **Observable:** External behavior, not internal state

## Core Principles

### 1. Atomic Requirements

Each requirement describes ONE capability only:

**Wrong (compound requirement):**
"The system shall classify documents and display results to reviewers and log all errors"

**Correct (atomic requirements):**
- FR-001: The system shall classify uploaded documents by type
- FR-002: The system shall display classification results to reviewers
- FR-003: The system shall log classification errors

### 2. Testable Requirements

Every requirement must be verifiable:

**Wrong (not testable):**
"The system shall be fast"

**Correct (testable):**
"The system shall display classification results within 5 seconds of document upload completion"

### 3. Unambiguous Requirements

Requirements have only one interpretation:

**Wrong (ambiguous):**
"The system shall handle errors gracefully"

**Correct (unambiguous):**
"When document classification fails, the system shall continue processing remaining documents and display error details to the reviewer"

### 4. User-Observable Behavior

Requirements describe external behavior, not internal implementation:

**Wrong (implementation):**
"The system shall use try-except blocks to catch exceptions"

**Correct (observable):**
"When errors occur, the system shall display error messages to reviewers"

## Prohibited Language

### NEVER Use Implementation Terms

**Return values or types:**
- Wrong: "return None", "return error response", "return dictionary"
- Correct: "provide error message to user", "make data available"

**Exception handling:**
- Wrong: "raise exception", "catch exceptions", "try/except"
- Correct: "display error", "notify user", "handle errors"

**Function calls or API invocations:**
- Wrong: "call API", "invoke method", "execute function"
- Correct: "retrieve data", "process request", "obtain results"

**Data structures:**
- Wrong: "dictionary", "list", "JSON object", "array"
- Correct: "collection", "set", "group", "list of items"

**Code-level control flow:**
- Wrong: "if/else", "loop through", "iterate over"
- Correct: "when condition occurs", "for each item", "process all"

**Technical implementation:**
- Wrong: "regex pattern", "deterministic extractor", "LLM fallback"
- Correct: "pattern matching", "automated extraction", "alternative method"

**Unverified performance metrics:**
- Wrong: "processes in 30 seconds", "real-time updates" (unless verified)
- Correct: "user sees progress as documents process" (no time claim)

### ALWAYS Use User-Facing Language

- "user sees", "reviewer receives", "system displays"
- "reviewer can identify", "user can access"
- "system continues processing", "applications are categorized"
- "reviewer is notified", "error message appears"

## Scope Boundaries

### What Belongs in Business Requirements

- Functional capabilities (what system does)
- User workflows and interactions
- Information visibility and access
- Decision-making capabilities
- Business rules and constraints
- Data inputs and outputs (from user perspective)

### What Does NOT Belong (Extract Instead)

When you encounter these, note for extraction to proper location:

**Coding Standards** → `.claude/rules/`
- Error handling patterns (try/except, logging)
- Code structure rules (module organization)
- Security patterns (input validation, sanitization)
- Testing practices (unit tests, mocking)

**Architecture Decisions** → `docs/decisions/DECISIONS.md`
- Technology choices (why Python, why LLM)
- Design patterns (multi-model consensus)
- Tradeoffs and rationale (speed vs accuracy)
- "Why we built it this way" explanations

**Implementation Details** → project setup documentation
- Specific library names (PyPDF2, pytesseract)
- Configuration details (API keys, timeouts)
- File paths and directory structure
- API endpoints or integration specifics

**Test Plans** → `tests/` or test documentation
- Test cases and test data
- Verification methods and procedures
- Coverage requirements
- Performance benchmarks

## Verification Methods

Each requirement should specify how it will be verified:

**Inspection:** Review of design documents, code, or interface
- Use for: UI layout, data formats, documentation

**Test:** Execute system with test cases
- Use for: Functional behavior, error handling, data processing

**Analysis:** Mathematical proof or simulation
- Use for: Algorithms, performance, capacity

**Demonstration:** Operate system for stakeholders
- Use for: User workflows, end-to-end scenarios

Example:
```markdown
**Verification Method:** Test
**Test Approach:** Upload document with known classification, verify system displays correct document type and usage tags
```

## Common Mistakes

### 1. Mixing Requirements with Implementation

**Wrong:**
"The system shall use GPT-4o-mini and Claude-3-Haiku to classify documents"

**Correct:**
"The system shall classify documents by type with 95% accuracy"

(Implementation details go in architecture decisions document)

### 2. Vague or Unmeasurable Requirements

**Wrong:**
"The system shall be user-friendly"

**Correct:**
"Grant reviewers shall complete document classification review in 3 clicks or fewer"

### 3. Compound Requirements

**Wrong:**
"The system shall classify documents, extract EINs, verify 501(c)(3) status, and generate reports"

**Correct:** Split into 4 separate requirements (FR-001 through FR-004)

### 4. Assuming Context

**Wrong:**
"When verifying, the system shall display results"

**Correct:**
"When verifying 501(c)(3) tax-exempt status, the system shall display EIN, confidence level, and verification source to the reviewer"

### 5. Including Test Cases in Requirements

**Wrong (in requirements doc):**
"Success Criteria: System passes all unit tests, integration tests show 90% coverage"

**Correct:**
Test plans belong in separate test documentation, not requirements documents

## Transaction Semantics Example

When describing batch processing or error handling:

**Wrong (implementation-focused):**
"System shall catch all exceptions and continue processing remaining items"

**Correct (user-focused with acceptance criteria):**

**FR-007: Partial Batch Processing Failure Handling**

**Requirement:**
When the system encounters errors processing individual documents within a batch, the system shall continue processing remaining documents without interruption.

**Acceptance Criteria:**
- Given a batch of 10 documents where document 3 fails classification
- When the system processes the batch
- Then documents 1, 2, 4-10 shall complete successfully and document 3 shall be marked as failed

- Given a document classification failure
- When the reviewer views the results
- Then the reviewer shall see the specific error type (unreadable PDF vs API failure vs invalid format)

- Given a temporary API service failure
- When the batch completes processing
- Then the system shall indicate which documents should be retried vs require manual intervention

## Examples

### Example 1: Error Visibility Requirement

```markdown
### FR-012: Classification Error Visibility

**Priority:** Must Have
**Source:** Grant Review Team
**Status:** Approved

**Requirement:**
The system shall display classification errors to reviewers, including error type and affected document name, when document classification fails.

**Rationale:**
Reviewers need visibility into which documents failed classification and why, to determine whether manual intervention is required or if automated retry is appropriate.

**Dependencies:** FR-001 (Document Classification)

**Acceptance Criteria:**
- Given a document that fails classification due to unreadable PDF
- When the reviewer views the classification results
- Then the system shall display "PDF unreadable" error with document filename

- Given a document that fails classification due to API timeout
- When the reviewer views the classification results
- Then the system shall display "API timeout - retry recommended" with document filename

- Given a batch where 3 of 10 documents fail classification
- When the reviewer views the results
- Then the system shall display 7 successful classifications and 3 error messages with distinct error types

**Verification Method:** Test
```

### Example 2: Data Access Requirement

```markdown
### FR-023: Historical Classification Results Access

**Priority:** Should Have
**Source:** Audit Compliance Team
**Status:** Proposed

**Requirement:**
Grant reviewers shall access historical classification results for any previously processed document, including classification timestamp, model used, and confidence score.

**Rationale:**
Audit trails require reviewers to verify past classification decisions and understand what information was available at decision time.

**Dependencies:** FR-001 (Document Classification), FR-018 (Result Storage)

**Acceptance Criteria:**
- Given a document classified 30 days ago
- When the reviewer searches for the document by filename
- Then the system shall display the original classification result with timestamp

- Given a classification result from historical data
- When the reviewer views the result
- Then the system shall display which model performed the classification and the confidence score

**Verification Method:** Inspection and Test
```

## Related Documentation

- `.claude/rules/` - Coding standards and implementation patterns
- `docs/decisions/DECISIONS.md` - Architecture decisions and rationale
- `docs/setup/` - Setup instructions and configuration guides
- `tests/` - Test plans and verification procedures

## Related Skills

**`audit-requirements-document`** - Automated enforcement of these standards
- Use after authoring requirements documents
- Detects violations through pattern matching
- Extracts misplaced content to appropriate destinations
- Generates cross-references between documents
- Maintains separation between requirements (WHAT) and implementation (HOW)

**Integration workflow:**
1. Author requirements using this skill (`writing-business-requirements`)
2. Audit document using `audit-requirements-document` skill
3. Review extracted content and verify categorization
4. Commit cleaned requirements and destination files

## References

- **BABOK v3** (Business Analysis Body of Knowledge) - International Institute of Business Analysis (IIBA)
- **IEEE 830-1998** - IEEE Recommended Practice for Software Requirements Specifications
- **ISO/IEC/IEEE 29148:2018** - Systems and software engineering — Life cycle processes — Requirements engineering
</content>
