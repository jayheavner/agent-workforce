# Requirements Document Content Classification Patterns

## Overview

This document defines the pattern detection rules that identify misplaced content in requirements documents. Each pattern category maps to a destination location where the content belongs.

**Purpose:** Enforce the requirements standards by detecting prohibited implementation language, technology specifics, architecture rationale, and test procedures.

**Usage:** The `audit-requirements-document` skill applies these patterns by hand to identify and report misplaced content along with a recommended destination for each finding.

## Pattern Categories

### 1. Implementation Details (Prohibited Language)

**Destination:** `.claude/rules/` (coding standards) OR project guidance

**Detection cues:**

#### Return Values and Types
```
return None / True / False / error / dict / list / tuple / response / result
returns a dictionary / list / tuple / object / response
```

Examples in requirements docs:
- Wrong: "The function shall return None when validation fails"
- Wrong: "Extractor returns error response if the file is unreadable"
- Wrong: "Returns a dictionary with the identifier and confidence score"

Should be:
- Correct: "The system shall indicate validation failure to the user"
- Correct: "The system shall provide error details when the file is unreadable"
- Correct: "The system shall provide the identifier and confidence score"

#### Exception Handling
```
raise / catch / except / try: / exception handling
throws an exception / error
```

Examples in requirements docs:
- Wrong: "System shall catch all exceptions and log errors"
- Wrong: "Validator raises an error when the format is invalid"
- Wrong: "Use try/except blocks to handle extraction failures"

Should be:
- Correct: "System shall handle errors and display error messages"
- Correct: "System shall reject invalid formats with an error message"
- Correct: "System shall handle extraction failures gracefully"

#### Function Calls and API Invocations
```
call / invoke / execute (a function / method / API / endpoint / service)
object.method(...) function-call syntax
calls the <name> function / method / API
```

Examples in requirements docs:
- Wrong: "System calls the classification API to classify the document"
- Wrong: "Invoke validate() before processing"
- Wrong: "classifier.classify(path, taxonomy) returns the result"

Should be:
- Correct: "System classifies documents using AI models"
- Correct: "System validates input before processing"
- Correct: "System provides classification results for uploaded documents"

#### Data Structures
```
dictionary / dict / list / array / tuple / JSON object / dataframe
key-value pairs / nested dict / list / structure
```

Examples in requirements docs:
- Wrong: "Store results in a dictionary keyed by document type"
- Wrong: "Return a list of extracted identifiers"
- Wrong: "The JSON object contains a tags array"

Should be:
- Correct: "Store results including the document type"
- Correct: "Provide a collection of extracted identifiers"
- Correct: "Results include usage tags"

#### Control Flow
```
if / else / elif / for loop / while / iterate over / loop through
conditional logic / statement / branching
```

Examples in requirements docs:
- Wrong: "If validation fails, return an error; else continue processing"
- Wrong: "Loop through all documents in the batch"
- Wrong: "Use conditional logic to determine the document type"

Should be:
- Correct: "When validation fails, display an error; otherwise continue processing"
- Correct: "Process all documents in the batch"
- Correct: "Determine the document type based on content"

#### Technical Implementation Terms
```
regex / regular expression / deterministic extractor / model fallback
algorithm / heuristic / optimization
class / module / function / method / variable
```

Examples in requirements docs:
- Wrong: "Use a regex pattern to extract the identifier from the text"
- Wrong: "Deterministic extractor handles clean input; model fallback handles errors"
- Wrong: "The Result class contains the identifier field"

Should be:
- Correct: "Extract the identifier from the text using pattern matching"
- Correct: "System uses automated extraction with fallback methods for difficult inputs"
- Correct: "Verification results include the identifier"

#### Performance Metrics (Unverified)
```
processes in N seconds / minutes
real-time / instantaneous / immediate (without verification)
within N ms / seconds / minutes (without verification)
```

Examples in requirements docs:
- Wrong: "System processes documents in 30 seconds" (not verified)
- Wrong: "Real-time updates as classification completes" (not verified)

Should be:
- Correct: "System provides progress visibility as documents process"
- Correct: "Users see classification results when processing completes"

**Notes:**
- Performance claims are acceptable if verified and measurable.
- Vague terms like "fast", "quickly", "efficiently" should be made specific or removed.

### 2. Technology Specifics

**Destination:** `docs/decisions/DECISIONS.md` (technology choices) OR `docs/setup/` (configuration)

**Detection cues:**

#### Library and Framework Names
```
Named PDF/OCR libraries, test frameworks, HTTP or data libraries
Named web frameworks
Named model providers or model versions (when describing HOW, not WHAT)
```

Examples in requirements docs:
- Wrong: "System uses <PDF library> to extract text from files"
- Wrong: "<OCR library> provides a fallback for scanned documents"
- Wrong: "<web framework> displays results to reviewers"

Should be extracted to:
- **Architecture decision:** "We chose <library> for extraction because it is lightweight and handles most inputs without OCR" -> `docs/decisions/DECISIONS.md`
- **Configuration:** "Install <OCR tool> for OCR support" -> `docs/setup/ocr-setup.md`

#### API Endpoints and URLs
```
Any https:// URL
endpoint / API URL / service URL: <value>
```

Examples in requirements docs:
- Wrong: "System calls a specific model-provider completions URL"
- Wrong: "External data endpoint: <a specific download URL>"

Should be extracted to:
- **Setup guide:** configuration and authentication instructions -> `docs/setup/`

#### Configuration Values
```
timeout / retry / threshold / limit = N
API key / secret / token / credential
```

Examples in requirements docs:
- Wrong: "API timeout set to 30 seconds"
- Wrong: "System retries failed requests 3 times"
- Wrong: "Confidence threshold = 0.95 for high-confidence classification"

Should be extracted to:
- **Configuration file:** default values and tuning parameters -> `config/*.json`
- **Setup guide:** environment-variable configuration -> `docs/setup/`

#### File Paths and Directory Structure
```
Absolute or project-relative file paths
data/ src/ tests/ config/ and similar directory references
```

Examples in requirements docs:
- Wrong: "Results stored in data/output/results.json"
- Wrong: "System reads the taxonomy from config/taxonomy.json"

Should be extracted to:
- **Project guidance:** file-organization conventions -> project guidance file

### 3. Architecture Rationale

**Destination:** `docs/decisions/DECISIONS.md`

**Detection cues:**

#### Design Decisions and Tradeoffs
```
we chose / decision to / rationale for / tradeoff / alternative / considered
why we / reason for using / benefits of
```

Examples in requirements docs:
- Wrong: "We chose multi-model consensus because single-model accuracy was insufficient"
- Wrong: "Rationale for the deterministic-first approach: speed and cost savings"
- Wrong: "Considered a pattern-only approach but rejected it due to input-quality issues"

Should be extracted to:
- **Architecture decisions:** design choices with context -> `docs/decisions/DECISIONS.md`

#### System Design Patterns
```
architecture / design pattern / consensus pattern / fallback chain
triple validation / multi-model / two-level classification
```

Examples in requirements docs:
- Wrong: "Triple validation strategy: deterministic then primary model then secondary model"
- Wrong: "Two-level taxonomy: a singular document type and an array of usage tags"

Should be extracted to:
- **Architecture decisions:** high-level design patterns -> `docs/decisions/DECISIONS.md`

#### Technology Comparison
```
compared to / versus / vs. / better than / faster than / more accurate
```

Examples in requirements docs:
- Wrong: "<library A> is faster than <library B> for clean inputs"
- Wrong: "<model A> provides better accuracy than <model B>"

Should be extracted to:
- **Architecture decisions:** technology-selection rationale -> `docs/decisions/DECISIONS.md`

### 4. Test Plans and Procedures

**Destination:** `tests/` (test files) OR test documentation

**Detection cues:**

#### Test Cases and Scenarios
```
test case / test scenario / test suite / unit test / integration test
test function names (test_...)
```

Examples in requirements docs:
- Wrong: "Test case: upload a document with a valid identifier, verify extraction succeeds"
- Wrong: "Unit tests validate the format with 23 test cases"
- Wrong: "test_classify_with_invalid_input() verifies error handling"

Should be extracted to:
- **Test files:** implement as actual test code -> `tests/unit/`, `tests/integration/`
- **Test documentation:** test strategy and approach -> `tests/README.md`

#### Coverage Requirements
```
coverage / 90% / 100% / test coverage / code coverage
all code paths / every branch / edge cases
```

Examples in requirements docs:
- Wrong: "Module shall have 90% test coverage"
- Wrong: "All error paths must be tested"
- Wrong: "Test edge cases: empty file, corrupted input, network timeout"

Should be extracted to:
- **Testing standards:** coverage requirements and policies -> `.claude/rules/testing.md`

#### Verification Methods
```
verification method / verification approach / test approach
mock / stub / fixture / test data
```

Examples in requirements docs:
- Wrong: "Verification method: mock the API responses and verify the classification logic"
- Wrong: "Use fixture data from a sample input file"

Should be extracted to:
- **Test documentation:** testing methodology -> `tests/README.md`

#### Assertions and Expected Results
```
assert / expect / should return / must pass (in a test context)
expected output / expected result / expected value (in a test context)
```

Examples in requirements docs:
- Wrong: "Expected result: document_type = 'invoice'"
- Wrong: "Assert that the confidence score is at least 0.95 for high confidence"

Should be extracted to:
- **Test files:** implement as assertions in test code -> `tests/`

## Pattern Application Strategy

### Detection Priority

1. **Exact phrase matching:** check for verbatim prohibited phrases first.
2. **Pattern cues:** apply the cues above to catch variations.
3. **Context analysis:** consider the surrounding text to avoid false positives.

### False Positive Prevention

**Allow implementation language in these contexts:**
- **Examples:** "Example: the extractor might use pattern matching..." (describing, not prescribing).
- **Quotes:** "The developer noted: 'we used try/except blocks here'" (attributed to someone).
- **Code blocks:** fenced code blocks are expected to contain implementation details.
- **Cross-references:** "See .claude/rules/testing.md for exception-handling patterns" (pointing elsewhere).

### Extraction Decision Rules

**Flag content when:**
- The pattern appears in a requirement statement or its rationale.
- The pattern describes HOW the system works (not WHAT it does).
- The content belongs in a different document type (rules, decisions, setup, tests).

**Do NOT flag when:**
- The pattern appears in a cross-reference or link.
- The pattern is in an example or illustration.
- The content is already in the correct location (for example a test file contains a test case).

## Destination Location Mapping

| Content Type | Destination | Purpose |
|--------------|-------------|---------|
| Exception handling patterns | `.claude/rules/python-style.md` | Coding standards |
| Error logging requirements | `.claude/rules/logging-security.md` | Security and logging standards |
| Module organization rules | `.claude/rules/project-standards.md` | Project conventions |
| Testing methodology | `.claude/rules/testing.md` | TDD and test standards |
| Technology choices | `docs/decisions/DECISIONS.md` | Architecture decisions |
| Design patterns | `docs/decisions/DECISIONS.md` | Architecture decisions |
| Tradeoff analysis | `docs/decisions/DECISIONS.md` | Architecture decisions |
| Library configuration | `docs/setup/*.md` | Setup instructions |
| API authentication | `docs/setup/api-setup.md` | Setup instructions |
| File organization | Project guidance file | Project guidance |
| Configuration defaults | `config/*.json` | Configuration files |
| Test cases | `tests/unit/`, `tests/integration/` | Test implementation |
| Test strategy | `tests/README.md` | Test documentation |
| Coverage requirements | `.claude/rules/testing.md` | Testing standards |

## Report Record Format

When a pattern flags misplaced content, record it in this form:

```yaml
violations:
  - type: "implementation_detail"
    category: "exception_handling"
    location: "docs/requirements/behavioral/verifier.md:45"
    content: "System shall catch all exceptions and log errors"
    destination: ".claude/rules/logging-security.md"
    suggested_replacement: "System shall handle errors and display error messages to users"
    severity: "high"  # high | medium | low

  - type: "architecture_rationale"
    category: "technology_choice"
    location: "docs/requirements/behavioral/classifier.md:78"
    content: "We chose the smaller model because it is faster and cheaper"
    destination: "docs/decisions/DECISIONS.md"
    suggested_replacement: "[Link to architecture decision: Model Selection]"
    severity: "medium"
```

**Severity Levels:**
- **High:** violates a core requirements principle (implementation in a requirement statement).
- **Medium:** useful information in the wrong location (architecture rationale in requirements).
- **Low:** minor clarity issue (vague language, missing cross-reference).

## Validation Criteria

Pattern definitions are correct when:
- All prohibited-language categories are covered.
- Each category includes a detection cue.
- Each category maps to a specific destination location.
- Examples demonstrate correct detection.
- False-positive prevention rules are documented.

## References

- **Source of the standards:** `~/.claude/skills/writing-business-requirements/SKILL.md` (the prohibited-language patterns this catalog enforces).
- **Standards:** BABOK v3, IEEE 830, ISO/IEC/IEEE 29148:2018 requirements-documentation standards.
